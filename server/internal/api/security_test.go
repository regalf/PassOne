package api

import (
	"net/http"
	"net/http/httptest"
	"regexp"
	"testing"

	"passone/internal/webui"
)

// A username must never be able to carry markup: it is rendered by the admin
// web UI and echoed by the API.
func TestUsernameValidation(t *testing.T) {
	ts, _ := newTestServer(t)

	bad := []string{
		`<img src=x onerror=alert(1)>`,
		`<script>alert(1)</script>`,
		`user"onmouseover="alert(1)`,
		`admin/admin`,
		`user name`,
		"user\nname",
		`<b>`,
	}
	for _, name := range bad {
		code, _ := post(t, ts.URL, "/api/v1/auth/setup", "", setupPayload(name, ""))
		if code != http.StatusBadRequest {
			t.Errorf("setup(%q) = %d, want 400", name, code)
		}
	}

	good := []string{
		"alice",
		"alice.bob",
		"alice_bob",
		"alice-bob",
		"alice@example.com",
		"Alice99",
	}
	for _, name := range good {
		code, _ := post(t, ts.URL, "/api/v1/auth/setup", "", setupPayload(name, ""))
		if code != http.StatusOK {
			t.Errorf("setup(%q) = %d, want 200", name, code)
		}
	}
}

// The admin API creates users too: it must apply the same rules.
func TestAdminCreateUserValidatesUsername(t *testing.T) {
	ts, _ := newTestServer(t)
	code, _ := post(t, ts.URL, "/api/v1/admin/users", "test-admin-token",
		map[string]any{"username": `<img src=x onerror=alert(1)>`})
	if code != http.StatusBadRequest {
		t.Fatalf("admin create = %d, want 400", code)
	}
}

// clientIP must not trust X-Forwarded-For from a non-loopback peer: the
// server binds to 0.0.0.0 by default, so a LAN client could otherwise
// spoof the header and bypass the rate limiter.
func TestClientIPIgnoresForwardedForFromRemotePeer(t *testing.T) {
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", nil)
	req.RemoteAddr = "192.168.1.50:54321"
	req.Header.Set("X-Forwarded-For", "1.2.3.4")

	if got := clientIP(req); got != "192.168.1.50" {
		t.Fatalf("clientIP = %q, want %q", got, "192.168.1.50")
	}
}

// A loopback peer is the local reverse proxy: the header is honoured.
func TestClientIPTrustsForwardedForFromLoopback(t *testing.T) {
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", nil)
	req.RemoteAddr = "127.0.0.1:54321"
	req.Header.Set("X-Forwarded-For", "1.2.3.4, 5.6.7.8")

	if got := clientIP(req); got != "1.2.3.4" {
		t.Fatalf("clientIP = %q, want %q", got, "1.2.3.4")
	}
}

// The rate limiter must keep a separate budget per endpoint, so that a burst
// on one endpoint cannot lock out the others.
func TestRateLimiterIsPerEndpoint(t *testing.T) {
	rl := NewRateLimiter(3, 60_000_000_000)

	for i := 0; i < 3; i++ {
		if !rl.Allow("login", "10.0.0.1") {
			t.Fatalf("login request %d denied", i)
		}
	}
	if rl.Allow("login", "10.0.0.1") {
		t.Fatal("login request 4 allowed, want denied")
	}
	// A different endpoint still has its own budget.
	if !rl.Allow("prelogin", "10.0.0.1") {
		t.Fatal("prelogin denied, want allowed")
	}
	// Another IP is independent too.
	if !rl.Allow("login", "10.0.0.2") {
		t.Fatal("login from another IP denied, want allowed")
	}
}

// The admin web UI must never render server data as markup.
func TestAdminUIHasNoInnerHTML(t *testing.T) {
	for _, name := range []string{"index.html", "admin.js"} {
		data, err := webui.Asset(name)
		if err != nil {
			t.Fatalf("reading %s: %v", name, err)
		}
		content := string(data)
		for _, pattern := range []string{
			`innerHTML\s*=`,
			`outerHTML\s*=`,
			`insertAdjacentHTML`,
			`document\.write`,
		} {
			if re, err := regexp.Compile(pattern); err == nil && re.MatchString(content) {
				t.Errorf("%s matches %q: server data could be interpreted as markup", name, pattern)
			}
		}
	}
}
