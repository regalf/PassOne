package api

import (
	"encoding/json"
	"io"
	"net/http"
	"testing"
)

// The invite flow: the client sends the invite token and gets back the user
// name of the account it belongs to, so the user does not have to type it.
func TestInviteLookup(t *testing.T) {
	ts, _ := newTestServer(t)

	// A pending user and its invite token.
	code, out := post(t, ts.URL, "/api/v1/admin/users", "test-admin-token",
		map[string]any{"username": "alice"})
	if code != http.StatusCreated {
		t.Fatalf("admin create = %d, want 201", code)
	}
	token, _ := out["invite_token"].(string)
	if token == "" {
		t.Fatal("no invite token returned")
	}

	// The token resolves to the user name.
	code, out = post(t, ts.URL, "/api/v1/auth/invite/lookup", "",
		map[string]any{"invite_token": token})
	if code != http.StatusOK {
		t.Fatalf("invite lookup = %d, want 200", code)
	}
	if out["username"] != "alice" {
		t.Errorf("username = %v, want alice", out["username"])
	}

	// An invalid token is refused.
	code, _ = post(t, ts.URL, "/api/v1/auth/invite/lookup", "",
		map[string]any{"invite_token": "not-a-token"})
	if code != http.StatusUnauthorized {
		t.Errorf("invite lookup (bad token) = %d, want 401", code)
	}

	// An empty token is refused.
	code, _ = post(t, ts.URL, "/api/v1/auth/invite/lookup", "",
		map[string]any{"invite_token": ""})
	if code != http.StatusUnauthorized {
		t.Errorf("invite lookup (empty token) = %d, want 401", code)
	}

	// The lookup does not consume the token: the account is still pending
	// and can be set up with the same token.
	code, out = post(t, ts.URL, "/api/v1/auth/setup", "", setupPayload("alice", token))
	if code != http.StatusOK {
		t.Fatalf("setup = %d, want 200 (%v)", code, out)
	}

	// Once the account is active the token is not valid anymore.
	code, _ = post(t, ts.URL, "/api/v1/auth/invite/lookup", "",
		map[string]any{"invite_token": token})
	if code != http.StatusUnauthorized {
		t.Errorf("invite lookup (used token) = %d, want 401", code)
	}
}

// The health endpoint tells the clients how the accounts are created.
func TestHealthReportsAllowRegistration(t *testing.T) {
	ts, _ := newTestServer(t)

	res, err := http.Get(ts.URL + "/health")
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	data, _ := io.ReadAll(res.Body)
	var out map[string]any
	if err := json.Unmarshal(data, &out); err != nil {
		t.Fatal(err)
	}
	if _, ok := out["allow_registration"]; !ok {
		t.Fatalf("the health response does not carry allow_registration: %v", out)
	}
	// The test server enables the direct registration.
	if out["allow_registration"] != true {
		t.Errorf("allow_registration = %v, want true", out["allow_registration"])
	}
}
