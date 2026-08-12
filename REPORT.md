# PassOne Security & Code Quality Audit Report

*Generated for AI agents - comprehensive analysis of the entire codebase*

---

## Executive Summary

This report documents all identified issues in the PassOne codebase (Go server + Flutter client) as of August 2026. Issues are categorized by severity: **CRITICAL**, **HIGH**, **MEDIUM**, **LOW**, and **INFO**.

**Total Issues Found: 27**

| Severity | Count |
|----------|-------|
| CRITICAL | 2 |
| HIGH | 4 |
| MEDIUM | 9 |
| LOW | 8 |
| INFO | 4 |

---

## CRITICAL Issues

### 1. Rate Limiter Memory Leak (Unbounded Map Growth)
**File:** `server/internal/api/ratelimit.go:8-46`

**Problem:** The `RateLimiter.buckets` map accumulates IPs indefinitely with no cleanup mechanism. Under sustained attack or normal long-term operation, this causes unbounded memory growth leading to OOM.

```go
type RateLimiter struct {
    mu      sync.Mutex
    limit   int
    window  time.Duration
    buckets map[string]*bucket  // Never cleaned up!
}
```

**Impact:** Denial of Service via memory exhaustion.

**Fix:** Implement periodic cleanup of expired buckets, or use a sliding window with a bounded data structure (e.g., `golang.org/x/time/rate` or a ring buffer).

---

### 2. Vault Cache Stored with Plaintext AuthHash (Offline Brute-Force)
**File:** `app/lib/state/settings.dart:187-201`, `app/lib/state/session.dart:258-270`

**Problem:** The `CachedVault` stores `authHash` (SHA-256 of KEK) in plaintext base64 on disk (`vault.cache.json`). An attacker with filesystem access can perform offline brute-force/dictionary attacks against the master password.

**Impact:** Full vault compromise if device is stolen/accessed.

**Fix:** Do not persist `authHash`. Instead, verify password by attempting to unwrap the vault key and decrypt the blob - if decryption fails (wrong key), the password is wrong. This is already done in `unlock()` but the cached `authHash` enables offline attack without touching the encrypted blob.

---

## HIGH Issues

### 3. Insecure Random Generation in VaultCrypto
**File:** `app/lib/crypto/vault_crypto.dart:14-21`

**Problem:** Uses `Random.secure()` in a loop instead of proper CSPRNG bulk generation:
```dart
static Uint8List randomBytes(int length) {
    final rng = Random.secure();
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = rng.nextInt(256);  // Inefficient, potential bias
    }
    return out;
}
```

**Impact:** Reduced entropy, performance issues, potential bias in byte distribution.

**Fix:** Use `Random.secure().nextBytes(out)` or `dart:math`'s `Random.secure()` properly.

---

### 4. No Certificate Pinning / MITM Vulnerable
**File:** `app/lib/api/client.dart:129-130`

**Problem:** Uses standard `http.Client()` without certificate pinning or custom trust anchors. Vulnerable to MITM on compromised networks.

**Impact:** Traffic interception, credential theft.

**Fix:** Implement certificate pinning or use a custom `SecurityContext` with pinned CA/sha256.

---

### 5. KDF Fallback Weakens Security Silently
**File:** `app/lib/crypto/kdf.dart:101-104`

**Problem:** When Argon2 native lib fails, falls back to PBKDF2 with deterministic iteration count derived from Argon2 params:
```dart
return _derivePbkdf2(password, salt,
    KdfParams.pbkdf2(iterations: (params.t * 1000).clamp(100000, 600000)), length);
```

**Impact:** User thinks they have Argon2id protection but actually gets PBKDF2. No user notification.

**Fix:** Log warning, persist the actual algorithm used, or fail hard if Argon2 unavailable.

---

### 6. Biometrics Only on Android (Platform Gap)
**File:** `app/lib/state/biometrics.dart:41-49`, `app/lib/state/session.dart:319-388`

**Problem:** `BiometricService.isAvailable()` returns `false` for non-Android platforms. iOS FaceID/TouchID via `local_auth` + Keychain not implemented.

**Impact:** No biometric unlock on iOS, inconsistent UX.

**Fix:** Implement iOS Keychain storage with `flutter_secure_storage` iOS options (`IOSOptions(accessibility: ...)`).

---

## MEDIUM Issues

### 7. Prelogin Timing Side-Channel (User Enumeration)
**File:** `server/internal/api/handlers_auth.go:203-228`

**Problem:** `handlePrelogin` does a DB lookup for the username. For non-existent users it generates random salt/KDF. The DB query timing differs from random generation, enabling user enumeration.

```go
u, err := s.store.GetUserByUsername(username)  // Timing varies
if err == nil { ... }  // User exists
// else generate random - different code path
```

**Impact:** Username enumeration via timing analysis.

**Fix:** Always perform the same operations - do a dummy query or use constant-time fake hash comparison for non-existent users.

---

### 8. Session Token Collision Not Checked
**File:** `server/internal/store/store.go:349-364`

**Problem:** `CreateSession` generates 32 random bytes but doesn't verify uniqueness before INSERT. While probability is negligible (~2^-256), it doesn't handle the unique constraint violation gracefully.

**Impact:** Theoretical session collision; unique constraint error returned as generic internal error.

**Fix:** Check `ErrConstraintViolation` on insert and retry with new token.

---

### 9. Vault Cache File World-Readable (Potential)
**File:** `app/lib/state/settings.dart:182-185`

**Problem:** Cache file created with default permissions:
```dart
final dir = await getApplicationSupportDirectory();
return File('${dir.path}${Platform.pathSeparator}vault.cache.json');
```

**Impact:** On rooted/jailbroken devices or shared systems, other apps/users may read the cache.

**Fix:** Set file permissions to 0600 (owner read/write only) after creation.

---

### 10. Recovery Key Displayed in Plaintext Dialog (Screenshot Risk)
**File:** `app/lib/ui/auth/register_screen.dart:99-138`

**Problem:** Recovery key shown in `AlertDialog` with `SelectableText` - can be captured by screenshots, screen recording, or accessibility services.

**Impact:** Recovery key exfiltration.

**Fix:** Use `FLAG_SECURE` on Android (`WindowManager.LayoutParams.FLAG_SECURE`), disable screenshots for the dialog, or show key in a custom secure view.

---

### 11. No Server-Side Password Policy Enforcement
**File:** `server/internal/api/handlers_auth.go:85-186`

**Problem:** Password complexity only enforced client-side (8 chars minimum in `register_screen.dart:59`). Server accepts any `auth_hash`.

**Impact:** Weak passwords possible via API bypass.

**Fix:** Enforce minimum entropy server-side, or at minimum document that client enforces policy.

---

### 12. Lock Timer Can Be Manipulated / Race Condition
**File:** `app/lib/state/session.dart:421-433`, `app/lib/main.dart:73-84`

**Problem:** Lock timer uses `Timer` which can be affected by system clock changes. The `_Root` widget listens for status changes but there's a race between `lock()` and UI navigation.

**Impact:** Vault may not lock when expected, or lock during active use.

**Fix:** Use monotonic clock (`DateTime.now().toUtc()` is wall clock), add `touch()` calls on user interaction, verify lock state on resume.

---

### 13. Biometric Key Not Rotated on Password Change
**File:** `app/lib/state/session.dart:548-618`, `app/lib/state/session.dart:390-404`

**Problem:** `changePassword` updates `wrappedKey` but `bioWrappedKey` in cache is NOT updated (still wraps old vaultKey with old bioKey). If biometrics enabled, the bioKey can still unwrap the OLD vaultKey.

```dart
final updated = CachedVault(
    ...
    wrappedKey: newWrapped,           // Updated
    bioWrappedKey: cache.bioWrappedKey,  // NOT updated!
    ...
);
```

**Impact:** After password change, biometric unlock still works with old vault key (stale data).

**Fix:** Re-wrap vault key with bioKey on password change, or clear bioWrappedKey requiring re-enrollment.

---

### 14. Token Not Validated on App Startup
**File:** `app/lib/state/session.dart:93-114`

**Problem:** `_init()` loads cache and sets status to `locked` if cache exists, but never validates the session token with the server. Token could be revoked/expired.

**Impact:** User sees "locked" state but token is invalid; unlock fails later with confusing error.

**Fix:** On startup, if cache exists, call `vaultGet` or a lightweight ping to validate token before setting `locked` state.

---

### 15. parseTime Silently Ignores Errors
**File:** `server/internal/store/store.go:449-454`

```go
func parseTime(s string) time.Time {
    t, _ := time.Parse(time.RFC3339Nano, s)  // Error ignored!
    return t
}
```

**Impact:** Malformed timestamps become zero time, causing logic bugs in vault revision ordering, session expiry.

**Fix:** Return error or use `time.Time{}` sentinel with proper handling.

---

## LOW Issues

### 16. Admin Token Only 24 Bytes (Inconsistent)
**File:** `server/cmd/passone/main.go:238`

```go
token, err := crypto.RandomHex(24)  // Other tokens use 32 bytes
```

**Impact:** Slightly less entropy than other tokens (192 vs 256 bits). Still secure but inconsistent.

**Fix:** Use 32 bytes for consistency.

---

### 17. No Secure Memory Zeroization (Dart Limitation)
**File:** `app/lib/state/session.dart` (multiple locations)

**Problem:** Dart/Flutter provides no way to securely zero memory. `vaultKey`, `kek`, `bioKey`, passwords remain in memory until GC.

**Impact:** Memory dump attacks can extract keys.

**Fix:** Document limitation; minimize key lifetime; use `Uint8List.fillRange(0, length, 0)` before letting go out of scope (best effort).

---

### 18. Rate Limiter Uses Fixed Window (Burst at Boundaries)
**File:** `server/internal/api/ratelimit.go:30-45`

**Problem:** Fixed window allows 2x burst at window boundaries (e.g., 20 req at 0:59, 20 req at 1:00).

**Impact:** Slightly higher effective rate than configured.

**Fix:** Use sliding window or token bucket algorithm.

---

### 19. Web UI Redirects Root to /admin/ (Info Leak)
**File:** `server/internal/webui/webui.go:22-26`

```go
if r.URL.Path == "/" || r.URL.Path == "/index.html" {
    http.Redirect(w, r, "/admin/", http.StatusFound)
    return
}
```

**Impact:** Reveals admin UI existence to unauthenticated visitors.

**Fix:** Return 404 or generic page for `/` when UI enabled; only redirect if admin token provided.

---

### 20. No CSRF Protection on State-Changing Endpoints
**File:** `server/internal/api/server.go` (all POST/PUT/DELETE)

**Problem:** API uses Bearer tokens only. While Bearer tokens in Authorization header are not automatically sent by browsers (no CSRF), if the API is ever called from a web context with cookies, CSRF would apply.

**Impact:** Low - current architecture uses token auth, not cookies.

**Fix:** Document that API is token-only; if cookies added later, implement CSRF.

---

### 21. Cache File Write Not Atomic
**File:** `app/lib/state/settings.dart:198-201`

```dart
Future<void> saveCache(CachedVault cache) async {
    final f = await _cacheFile();
    await f.writeAsString(jsonEncode(cache.toJson()));  // Not atomic
}
```

**Impact:** Partial write on crash/power loss corrupts cache.

**Fix:** Write to temp file + rename (atomic on POSIX).

---

### 22. Debug/Logging Could Leak Sensitive Data
**File:** `server/cmd/passone/main.go:108`, `server/internal/api/middleware.go:39-45`

**Problem:** Admin token logged on first startup (`log.Info("admin token generated", "admin_token", ...)`). Request logging includes full path but not body - OK.

**Impact:** Admin token in logs if log level is Info.

**Fix:** Log only token prefix/suffix, or hash.

---

### 23. Inconsistent Error Codes (Client-Server Mismatch)
**File:** `server/internal/api/server.go:111-119`, `app/lib/api/client.dart:139-152`

**Problem:** Server returns `"code": "resource not found"` for `ErrNotFound`, but client expects specific codes. Some endpoints return custom error structures (e.g., `vaultPut` returns `current_revision`).

**Impact:** Client error handling fragile.

**Fix:** Standardize error response format across all endpoints.

---

## INFO / Best Practice Issues

### 24. Go Version 1.26.5 (Future/Unreleased)
**File:** `server/go.mod:3`

```go
go 1.26.5  // As of Aug 2026, latest stable is 1.22.x or 1.23.x
```

**Impact:** May not compile on standard toolchains.

**Fix:** Use a released Go version (e.g., `1.22` or `1.23`).

---

### 25. Missing Security Headers (HSTS, CSP, etc.)
**File:** `server/internal/api/server.go`, `server/internal/webui/webui.go`

**Problem:** No security headers set on responses (HSTS, X-Frame-Options, CSP, etc.).

**Impact:** Defense-in-depth missing.

**Fix:** Add middleware to set security headers.

---

### 26. No Request Size Limits on All Endpoints
**File:** `server/internal/api/server.go:91-94`

```go
func decodeJSON(w http.ResponseWriter, r *http.Request, v any) error {
    dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 10<<20))  // 10MB
    return dec.Decode(v)
}
```

**Problem:** 10MB limit only on JSON decode. Multipart/form-data or other content types not limited.

**Impact:** Potential DoS via large uploads.

**Fix:** Wrap all handlers with `http.MaxBytesReader` at middleware level.

---

### 27. Vault Merge Logic (LWW) Loses Concurrent Edits
**File:** `app/lib/state/session.dart:722-736`

```dart
VaultData _mergeVaults(VaultData local, VaultData remote) {
    // Last-Writer-Wins per entry by updatedAt
    // No conflict resolution for same entry edited on two devices
}
```

**Impact:** Silent data loss if same entry edited offline on two devices.

**Fix:** Implement proper CRDT or at least flag conflicts for user resolution.

---

## Summary of Recommended Fixes Priority

| Priority | Issues |
|----------|--------|
| **Immediate** | 1, 2, 3, 4 |
| **High** | 5, 6, 7, 8, 9, 10 |
| **Medium** | 11, 12, 13, 14, 15 |
| **Low** | 16-23 |
| **Cleanup** | 24-27 |

---

## Security Architecture Notes

### Good Practices Observed
- ✅ End-to-end encryption: server never sees plaintext vault
- ✅ Argon2id as primary KDF with PBKDF2 fallback
- ✅ Constant-time comparisons (`crypto.SecureEqual`, `subtle.ConstantTimeCompare`)
- ✅ Session tokens hashed in DB (SHA-256)
- ✅ Recovery key wrapped separately from master key
- ✅ Optimistic locking on vault revisions (CAS)
- ✅ Biometric key stored in Android Keystore (hardware-backed)
- ✅ SQL parameterized queries (no injection)
- ✅ TLS recommended, admin token random generation
- ✅ Rate limiting on auth endpoints
- ✅ Audit logging of HTTP requests

### Threat Model Assumptions
- Server is honest-but-curious (E2E encryption protects vault)
- Client device may be compromised (cache encryption mitigates)
- Network may be MITM (certificate pinning missing - Issue 4)
- Backup file contains all secrets (Issue 2 applies to backup too)

---

## Files Not Analyzed (Build Artifacts / Tests)
- `server/test/*` - Test database files
- `app/build/*` - Flutter build artifacts
- `dist/*` - Distribution binaries
- `*.apk`, `*.tar.gz` - Release artifacts

---

*End of Report*