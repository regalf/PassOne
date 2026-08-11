package api

import (
	"bytes"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"

	"passone/internal/config"
	"passone/internal/crypto"
	"passone/internal/store"
)

func newTestServer(t *testing.T) (*httptest.Server, *store.Store) {
	t.Helper()
	cfg := config.Default()
	cfg.Addr = "127.0.0.1:0"
	cfg.AllowRegistration = true
	cfg.AdminToken = "test-admin-token"
	st, err := store.Open(filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { st.Close() })
	srv := New(cfg, st, slog.New(slog.NewTextHandler(io.Discard, nil)))
	ts := httptest.NewServer(srv.Routes())
	t.Cleanup(ts.Close)
	return ts, st
}

func post(t *testing.T, url, path, token string, body any) (int, map[string]any) {
	t.Helper()
	b, _ := json.Marshal(body)
	req, _ := http.NewRequest("POST", url+path, bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	data, _ := io.ReadAll(res.Body)
	var out map[string]any
	_ = json.Unmarshal(data, &out)
	return res.StatusCode, out
}

func get(t *testing.T, url, path, token string) (int, map[string]any) {
	t.Helper()
	req, _ := http.NewRequest("GET", url+path, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	data, _ := io.ReadAll(res.Body)
	var out map[string]any
	_ = json.Unmarshal(data, &out)
	return res.StatusCode, out
}

func put(t *testing.T, url, path, token string, body any) (int, map[string]any) {
	t.Helper()
	b, _ := json.Marshal(body)
	req, _ := http.NewRequest("PUT", url+path, bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	data, _ := io.ReadAll(res.Body)
	var out map[string]any
	_ = json.Unmarshal(data, &out)
	return res.StatusCode, out
}

// setupPayload builds a realistic setup payload.
func setupPayload(username, invite string) map[string]any {
	p := map[string]any{
		"username":               username,
		"auth_hash_b64":          crypto.EncodeBase64([]byte("fake-auth-hash-32-bytes-long!!!")),
		"salt_b64":               crypto.EncodeBase64([]byte("fake-salt")),
		"kdf": map[string]any{
			"algorithm": "argon2id",
			"params":    map[string]any{"m": 65536, "t": 3, "p": 4},
		},
		"vault_key_wrapped_b64": crypto.EncodeBase64([]byte("wrapped-key")),
		"vault_blob_b64":        crypto.EncodeBase64([]byte("encrypted-vault-blob")),
		"vault_nonce_b64":       crypto.EncodeBase64([]byte("nonce-nonce")),
	}
	if invite != "" {
		p["invite_token"] = invite
	}
	return p
}

func TestHealth(t *testing.T) {
	ts, _ := newTestServer(t)
	res, err := http.Get(ts.URL + "/health")
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	if res.StatusCode != 200 {
		t.Fatalf("status = %d", res.StatusCode)
	}
}

func TestPrelogin(t *testing.T) {
	ts, _ := newTestServer(t)
	// Unknown user -> status unknown + random salt + default kdf
	code, out := post(t, ts.URL, "/api/v1/auth/prelogin", "", map[string]any{"username": "ghost"})
	if code != 200 {
		t.Fatalf("prelogin = %d", code)
	}
	if out["status"] != "unknown" || out["salt_b64"] == "" {
		t.Fatalf("prelogin unknown = %v", out)
	}

	// Real user setup, then prelogin must reflect the salt and kdf
	post(t, ts.URL, "/api/v1/auth/setup", "", setupPayload("henry", ""))
	code, out = post(t, ts.URL, "/api/v1/auth/prelogin", "", map[string]any{"username": "henry"})
	if code != 200 {
		t.Fatalf("prelogin = %d", code)
	}
	if out["status"] != "active" {
		t.Fatalf("status = %v", out["status"])
	}
	if out["salt_b64"] != crypto.EncodeBase64([]byte("fake-salt")) {
		t.Fatalf("salt non tornato: %v", out["salt_b64"])
	}
}

func TestRegistrationAndLogin(t *testing.T) {
	ts, _ := newTestServer(t)
	code, out := post(t, ts.URL, "/api/v1/auth/setup", "", setupPayload("alice", ""))
	if code != 200 {
		t.Fatalf("setup status = %d, body = %v", code, out)
	}
	token := out["token"].(string)
	if token == "" {
		t.Fatal("token vuoto")
	}
	code, out = post(t, ts.URL, "/api/v1/auth/login", "", map[string]any{
		"username": "alice", "auth_hash_b64": crypto.EncodeBase64([]byte("fake-auth-hash-32-bytes-long!!!")),
	})
	if code != 200 {
		t.Fatalf("login status = %d, body = %v", code, out)
	}
	if out["token"] == "" {
		t.Fatal("login senza token")
	}
}

func TestLoginWrongPassword(t *testing.T) {
	ts, _ := newTestServer(t)
	post(t, ts.URL, "/api/v1/auth/setup", "", setupPayload("bob", ""))
	code, _ := post(t, ts.URL, "/api/v1/auth/login", "", map[string]any{
		"username": "bob", "auth_hash_b64": crypto.EncodeBase64([]byte("wrong-hash")),
	})
	if code != 401 {
		t.Fatalf("status = %d, atteso 401", code)
	}
}

func TestVaultGetPutAndConflict(t *testing.T) {
	ts, _ := newTestServer(t)
	code, out := post(t, ts.URL, "/api/v1/auth/setup", "", setupPayload("carol", ""))
	if code != 200 {
		t.Fatal("setup fallito")
	}
	token := out["token"].(string)

	code, out = get(t, ts.URL, "/api/v1/vault", token)
	if code != 200 {
		t.Fatalf("vault get = %d", code)
	}
	if out["vault_revision"].(float64) != 1 {
		t.Fatalf("revision = %v", out["vault_revision"])
	}

	code, out = put(t, ts.URL, "/api/v1/vault", token, map[string]any{
		"base_revision": 1,
		"vault_blob_b64": crypto.EncodeBase64([]byte("new-blob")),
		"vault_nonce_b64": crypto.EncodeBase64([]byte("nonce2")),
	})
	if code != 200 {
		t.Fatalf("vault put = %d, body=%v", code, out)
	}
	if out["vault_revision"].(float64) != 2 {
		t.Fatalf("revision dopo put = %v", out["vault_revision"])
	}

	// Conflict: stale base_revision.
	code, out = put(t, ts.URL, "/api/v1/vault", token, map[string]any{
		"base_revision": 1,
		"vault_blob_b64": crypto.EncodeBase64([]byte("stale")),
		"vault_nonce_b64": crypto.EncodeBase64([]byte("nonce3")),
	})
	if code != 409 {
		t.Fatalf("atteso 409, status = %d", code)
	}
	if out["current_revision"].(float64) != 2 {
		t.Fatalf("current_revision = %v", out["current_revision"])
	}
}

func TestPendingInviteFlow(t *testing.T) {
	ts, st := newTestServer(t)
	token, err := st.CreatePendingUser("dave")
	if err != nil {
		t.Fatal(err)
	}
	// Login while pending -> 409
	code, out := post(t, ts.URL, "/api/v1/auth/login", "", map[string]any{
		"username": "dave", "auth_hash_b64": crypto.EncodeBase64([]byte("x")),
	})
	if code != 409 {
		t.Fatalf("atteso 409 pending, status=%d", code)
	}
	// Setup with wrong invite token -> 403
	code, _ = post(t, ts.URL, "/api/v1/auth/setup", "", setupPayload("dave", "wrong-token"))
	if code != 403 {
		t.Fatalf("atteso 403, status=%d", code)
	}
	// Correct setup
	code, out = post(t, ts.URL, "/api/v1/auth/setup", "", setupPayload("dave", token))
	if code != 200 {
		t.Fatalf("setup con invite = %d, body=%v", code, out)
	}
	// login now works
	code, _ = post(t, ts.URL, "/api/v1/auth/login", "", map[string]any{
		"username": "dave", "auth_hash_b64": crypto.EncodeBase64([]byte("fake-auth-hash-32-bytes-long!!!")),
	})
	if code != 200 {
		t.Fatalf("login post-setup = %d", code)
	}
}

func TestAdminUsers(t *testing.T) {
	ts, _ := newTestServer(t)
	adm := "Bearer test-admin-token"

	req, _ := http.NewRequest("POST", ts.URL+"/api/v1/admin/users", bytes.NewReader([]byte(`{"username":"erin"}`)))
	req.Header.Set("Authorization", adm)
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	var out map[string]any
	_ = json.NewDecoder(res.Body).Decode(&out)
	res.Body.Close()
	if res.StatusCode != 201 {
		t.Fatalf("create user = %d, body=%v", res.StatusCode, out)
	}
	if out["invite_token"] == "" {
		t.Fatal("manca invite_token")
	}

	req, _ = http.NewRequest("GET", ts.URL+"/api/v1/admin/users", nil)
	req.Header.Set("Authorization", adm)
	res, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	res.Body.Close()
	if res.StatusCode != 200 {
		t.Fatalf("list users = %d", res.StatusCode)
	}

	// Wrong admin token -> 401
	res, err = http.Get(ts.URL + "/api/v1/admin/users")
	if err != nil {
		t.Fatal(err)
	}
	res.Body.Close()
	if res.StatusCode != 401 {
		t.Fatalf("admin senza token = %d, atteso 401", res.StatusCode)
	}
}

func TestChangePasswordAndLogoutAll(t *testing.T) {
	ts, _ := newTestServer(t)
	_, out := post(t, ts.URL, "/api/v1/auth/setup", "", setupPayload("frank", ""))
	token := out["token"].(string)

	// Password change with wrong old password -> 401
	code, _ := post(t, ts.URL, "/api/v1/auth/change-password", token, map[string]any{
		"old_auth_hash_b64": crypto.EncodeBase64([]byte("wrong-old")),
		"new":               map[string]any{},
	})
	if code != 401 {
		t.Fatalf("atteso 401, status=%d", code)
	}

	// Correct password change
	code, _ = post(t, ts.URL, "/api/v1/auth/change-password", token, map[string]any{
		"old_auth_hash_b64": crypto.EncodeBase64([]byte("fake-auth-hash-32-bytes-long!!!")),
		"new": map[string]any{
			"auth_hash_b64":        crypto.EncodeBase64([]byte("new-hash-32-bytes-long!!!!!")),
			"salt_b64":             crypto.EncodeBase64([]byte("new-salt")),
			"kdf":                  map[string]any{"algorithm": "argon2id", "params": map[string]any{"m": 65536, "t": 3, "p": 4}},
			"vault_key_wrapped_b64": crypto.EncodeBase64([]byte("new-wrapped")),
		},
	})
	if code != 200 {
		t.Fatalf("change-password = %d", code)
	}

	// logout-all
	req, _ := http.NewRequest("POST", ts.URL+"/api/v1/auth/logout-all", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	res.Body.Close()
	if res.StatusCode != 204 {
		t.Fatalf("logout-all = %d", res.StatusCode)
	}
	// The old session is now invalid
	code, _ = get(t, ts.URL, "/api/v1/vault", token)
	if code != 401 {
		t.Fatalf("atteso 401 dopo logout-all, status=%d", code)
	}
}

func TestRecoverFlow(t *testing.T) {
	ts, _ := newTestServer(t)
	// Setup with recovery key
	p := setupPayload("grace", "")
	p["recovery_hash_b64"] = crypto.EncodeBase64([]byte("recovery-hash-1"))
	p["vault_key_wrapped_recov_b64"] = crypto.EncodeBase64([]byte("wrapped-recov"))
	_, out := post(t, ts.URL, "/api/v1/auth/setup", "", p)
	token := out["token"].(string)

	// Recover-payload: verifies the key and returns the encrypted vault without burning it
	code, out := post(t, ts.URL, "/api/v1/auth/recover-payload", "", map[string]any{
		"username": "grace", "recovery_hash_b64": crypto.EncodeBase64([]byte("recovery-hash-1")),
	})
	if code != 200 {
		t.Fatalf("recover-payload = %d, body=%v", code, out)
	}
	if out["vault_key_wrapped_recov_b64"] != crypto.EncodeBase64([]byte("wrapped-recov")) {
		t.Fatalf("payload recov key sbagliata: %v", out["vault_key_wrapped_recov_b64"])
	}
	// The key is NOT burned by recover-payload
	code, _ = post(t, ts.URL, "/api/v1/auth/recover-payload", "", map[string]any{
		"username": "grace", "recovery_hash_b64": crypto.EncodeBase64([]byte("recovery-hash-1")),
	})
	if code != 200 {
		t.Fatalf("recover-payload deve essere idempotente, status=%d", code)
	}

	// Recovery with wrong hash -> 401
	code, _ = post(t, ts.URL, "/api/v1/auth/recover", "", map[string]any{
		"username": "grace", "recovery_hash_b64": crypto.EncodeBase64([]byte("wrong")),
		"new": map[string]any{},
	})
	if code != 401 {
		t.Fatalf("atteso 401, status=%d", code)
	}

	// Correct recovery -> new session, burned key, revoked sessions
	code, out = post(t, ts.URL, "/api/v1/auth/recover", "", map[string]any{
		"username": "grace", "recovery_hash_b64": crypto.EncodeBase64([]byte("recovery-hash-1")),
		"new": map[string]any{
			"auth_hash_b64": crypto.EncodeBase64([]byte("new-hash-after-recovery")),
			"salt_b64":      crypto.EncodeBase64([]byte("salt-2")),
			"kdf":           map[string]any{"algorithm": "argon2id", "params": map[string]any{"m": 65536, "t": 3, "p": 4}},
			"vault_key_wrapped_b64": crypto.EncodeBase64([]byte("wrapped-2")),
			"recovery_hash_b64":     crypto.EncodeBase64([]byte("recovery-hash-2")),
			"vault_key_wrapped_recov_b64": crypto.EncodeBase64([]byte("wrapped-recov-2")),
		},
	})
	if code != 200 {
		t.Fatalf("recover = %d, body=%v", code, out)
	}
	newToken := out["token"].(string)

	// Old session revoked
	code, _ = get(t, ts.URL, "/api/v1/vault", token)
	if code != 401 {
		t.Fatalf("atteso 401 vecchia sessione, status=%d", code)
	}
	// New session works
	code, out = get(t, ts.URL, "/api/v1/vault", newToken)
	if code != 200 {
		t.Fatalf("vault con nuova sessione = %d", code)
	}
	if out["recovery_enabled"] != true {
		t.Fatalf("recovery_enabled = %v", out["recovery_enabled"])
	}
	// The old recovery key is burned
	code, _ = post(t, ts.URL, "/api/v1/auth/recover", "", map[string]any{
		"username": "grace", "recovery_hash_b64": crypto.EncodeBase64([]byte("recovery-hash-1")),
		"new": map[string]any{
			"auth_hash_b64": crypto.EncodeBase64([]byte("x")),
			"salt_b64":      crypto.EncodeBase64([]byte("y")),
			"kdf":           map[string]any{"algorithm": "argon2id", "params": map[string]any{"m": 65536, "t": 3, "p": 4}},
			"vault_key_wrapped_b64": crypto.EncodeBase64([]byte("z")),
		},
	})
	if code != 401 {
		t.Fatalf("atteso 401 recovery bruciata, status=%d", code)
	}
}

func TestRegistrationDisabled(t *testing.T) {
	cfg := config.Default()
	cfg.AllowRegistration = false
	cfg.AdminToken = "x"
	st, err := store.Open(filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	srv := New(cfg, st, slog.New(slog.NewTextHandler(io.Discard, nil)))
	ts := httptest.NewServer(srv.Routes())
	defer ts.Close()

	code, _ := post(t, ts.URL, "/api/v1/auth/setup", "", setupPayload("noreg", ""))
	if code != 403 {
		t.Fatalf("atteso 403, status=%d", code)
	}
}
