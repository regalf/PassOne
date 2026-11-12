# PassOne

Self-hostable password manager with **end-to-end encryption** (Go server + Flutter app).
The server never sees your passwords: it only stores hashes (SHA-256 of the derived key) and
AES-256-GCM encrypted blobs; no data can be decrypted server-side.

## Quick start — server

Prerequisites: Go 1.26+.

```bash
cd server

# 1. Build the single binary
go build -o passone ./cmd/passone

# 2. Generate the configuration (creates config.yaml with a random admin token)
./passone config init

# 3. Start the server (default: http://0.0.0.0:8321)
./passone serve
```

On first start, if `admin_token` is not in `config.yaml`, one is generated and printed: **save it**.

### Creating a user

```bash
# Creates the user (status "pending") and prints the one-time invite token
./passone user create <username>

# Or, if direct registration is enabled (allow_registration: true),
# users can sign up directly from the app.
```

Usernames accept ASCII letters, digits and `- _ . @ +` (max 64 characters).

Other useful commands:

```bash
./passone user list
./passone user disable <username>
./passone user reset-invite <username>
./passone backup --out backup.json    # encrypted blobs + auth material
```

### Admin web UI

With the web UI enabled (default), open `http://<server>:8321/admin/` and enter the **admin token**:
here you can create users and view invite tokens.

The admin token is kept in memory only (never in `localStorage`) and is compared in constant time.

### Listening on the local network / publicly

By default the server listens on **all interfaces** (`0.0.0.0:8321`) so that the mobile app
can reach it out of the box, and **direct registration is disabled** (users are created with an
invite token). The server logs a warning at startup for both conditions.

To restrict the server to this machine, edit `config.yaml` (or use `--addr`):

```yaml
addr: "127.0.0.1:8321"   # only reachable locally (use a reverse proxy for HTTPS)
allow_registration: false # manage users via invite tokens
```

`X-Forwarded-For` is only trusted when the request comes from **loopback**: the server binds to
`0.0.0.0` by default, so trusting the header from any private peer would let a LAN client spoof
its IP and bypass the rate limiter.

### HTTPS (recommended)

The server supports direct TLS (`tls_cert`/`tls_key` in config.yaml) or a reverse proxy.
With Caddy:

```
example.com {
    reverse_proxy 127.0.0.1:8321
}
```

Without HTTPS the server logs a warning: the transport is not encrypted, but the data stays
unreadable (AEAD) to anyone who intercepts it; only metadata (username, timestamps) is exposed.
The mobile app asks for an explicit confirmation before connecting to an `http://` address,
because the password verifier and the session token would travel in cleartext.

## Quick start — desktop app (Linux)

Prerequisites: Flutter SDK.

```bash
cd app
flutter pub get

# Release build
flutter build linux --release

# Run
./build/linux/x64/release/bundle/passone_app
```

Alternatively, use the build script below to build everything with one command.

### First access

1. Enter the **server URL** (e.g. `https://passone.example.com` or `http://192.168.1.10:8321`).
2. If the user already exists (created by an admin): username + master password + **invite token**.
   If direct registration is active: just username + master password.
3. Enable the **recovery key** (recommended): it is shown only once, save it.
4. The vault is ready: add your first entries with the **New** button.

The vault locks automatically (1/2/5/10 minutes) and unlocks with the master password,
even offline (local cache).

## Android

Building the APK requires the Android SDK. With the toolchain installed:

```bash
cd app
flutter build apk --release
```

## Build everything with one script

`scripts/build.py` checks the toolchain (Go, Flutter, Dart, Java, cmake, ninja,
clang, GTK3, Android SDK, appimagetool), reports what is present and what is
missing, and then builds the server, the Linux release bundle, the Android APK
and the Linux AppImage. Artifacts land in `server/dist/`.

```bash
python3 scripts/build.py --check-only      # only the environment report
python3 scripts/build.py                   # full build pipeline
python3 scripts/build.py --download-tools  # fetch appimagetool if missing
```

Flags: `--no-server`, `--no-linux`, `--no-apk`, `--no-appimage`.

Requires Python 3 and the standard toolchain. On the first run it builds
incrementally; a clean rebuild is done by deleting `app/build/` first.

### Toolchain versions

| Tool | Version | Notes |
|---|---|---|
| Go | 1.26+ | server build |
| Flutter | 3.50.0 (Dart 3.14.0) | app build; `sdk: ^3.12.2` in `pubspec.yaml` |
| Java | 17+ | Android Gradle Plugin 9.1.1 |
| Gradle | 9.3.1 | `android/gradle/wrapper/gradle-wrapper.properties` |
| Android SDK | platform 34+, build-tools 35+/36+ | `platforms;android-35`, `platforms;android-36` |

The Android SDK can be pointed at with `ANDROID_HOME` (or `ANDROID_SDK_ROOT`);
`scripts/build.py` reads it from the environment or from `android/local.properties`.

## Tests

```bash
cd server && go test ./...          # server unit + API tests

cd app && flutter test              # app tests
```

The app tests include end-to-end tests that need the Go server running:

```bash
cd server
go build -o test/passone ./cmd/passone
./test/passone serve --config test/integration.yaml        # http://127.0.0.1:18334
./test/passone serve --config test/integration-tls.yaml    # https://127.0.0.1:18331
```

The TLS pairing test compares the fingerprint computed by the Dart client with
the one printed by the Go server. When the test server has generated a new key
pair, export the expected value:

```bash
PASSONE_CONFIG=test/integration-tls.yaml ./test/passone tls fingerprint
export PASSONE_TEST_FINGERPRINT=<fingerprint>
```

## Backup and recovery

- `passone backup` exports the encrypted blobs and the authentication material to a JSON file:
  keep it on a safe medium. **The backup contains the password verifier and the TLS private key**:
  treat it like a master password, never like a plain backup.
- To restore, the data must be re-inserted into the SQLite database (the `passone.db` file) — a
  dedicated command will be available in the future.

## Security notes

- The **recovery key** lets you reset a forgotten password **only if it was enabled**.
  Without it, a forgotten password = wiped vault (like Bitwarden).
- If enabled, the recovery key is **burned after every use** and each reset revokes all
  sessions.
- Auto-lock is client-side: it protects against device theft, not against the server.
- The server is a blind store: it holds the password verifier (`sha256` of the derived key), so a
  leak of `passone.db` allows an **offline** brute-force of the master password. Argon2id
  (64 MiB, t=3, p=4) makes that expensive, but it is not impossible.
- The key derivation algorithm is **never silently downgraded**: if Argon2id is unavailable on the
  device, the app reports the failure instead of falling back to a weaker KDF (which would
  otherwise be reported as a wrong password).
- The admin web UI renders every value through the DOM (never as markup) and is served with a
  strict `Content-Security-Policy`; usernames are restricted to a safe character set on the
  server.
