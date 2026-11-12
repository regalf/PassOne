package api

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"net"
	"net/http"
	"strings"
	"time"

	"passone/internal/crypto"
	"passone/internal/store"
)

type ctxKey int

const (
	ctxUserKey ctxKey = iota
	ctxTokenKey
)

// maxBodyBytes caps the size of every request body (defense in depth; the
// JSON decoders already apply the same limit).
const maxBodyBytes = 10 << 20

// contentSecurityPolicy is applied to every response.
//
// The admin web UI ships its CSS and JS as separate files, so a strict policy
// is possible: no inline script, no inline style attributes, no plugins, no
// framing. This is the second layer of defence against XSS in the UI (the
// first one being that the UI never renders server data as markup).
const contentSecurityPolicy = "default-src 'none'; " +
	"script-src 'self'; " +
	"style-src 'self'; " +
	"img-src 'self' data:; " +
	"connect-src 'self'; " +
	"base-uri 'none'; " +
	"form-action 'none'; " +
	"frame-ancestors 'none'"

// SecureHeaders sets hardening headers on every response.
//
// It is exported so that it can be applied to the *outermost* handler: the
// admin web UI is mounted next to the API, outside the API router, and would
// otherwise be served without any hardening header.
func SecureHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("Content-Security-Policy", contentSecurityPolicy)
		w.Header().Set("Cross-Origin-Opener-Policy", "same-origin")
		w.Header().Set("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
		// HSTS only makes sense over HTTPS (direct TLS or behind a proxy that
		// forwards the scheme). Setting it on plain HTTP would be harmful.
		if r.TLS != nil || strings.EqualFold(r.Header.Get("X-Forwarded-Proto"), "https") {
			w.Header().Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		}
		next.ServeHTTP(w, r)
	})
}

// secureHeaders sets hardening headers on every response.
func secureHeaders(next http.Handler) http.Handler {
	return SecureHeaders(next)
}

// limitBody caps the size of every request body.
func limitBody(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
		next.ServeHTTP(w, r)
	})
}

func randomHex(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return ""
	}
	return hex.EncodeToString(b)
}

func (s *Server) userFrom(ctx context.Context) *store.User {
	u, _ := ctx.Value(ctxUserKey).(*store.User)
	return u
}

// tokenFrom returns the session token stored by the authed middleware.
func tokenFrom(ctx context.Context) string {
	t, _ := ctx.Value(ctxTokenKey).(string)
	return t
}

// logged logs every request.
func (s *Server) logged(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: 200}
		next(sw, r)
		s.log.Info("http",
			"method", r.Method,
			"path", r.URL.Path,
			"status", sw.status,
			"duration", time.Since(start).Round(time.Microsecond).String(),
			"ip", clientIP(r),
		)
	}
}

// authed requires a valid session.
func (s *Server) authed(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token := bearerToken(r)
		if token == "" {
			writeErr(w, http.StatusUnauthorized, "missing session", "no_session")
			return
		}
		u, err := s.store.GetUserBySessionToken(token)
		if err != nil {
			writeErr(w, http.StatusUnauthorized, "invalid or expired session", "bad_session")
			return
		}
		if u.Status != store.StatusActive {
			writeErr(w, http.StatusForbidden, "account not active", "inactive")
			return
		}
		next(w, r.WithContext(context.WithValue(
			context.WithValue(r.Context(), ctxUserKey, u), ctxTokenKey, token)))
	}
}

// adminOnly requires the configured admin token.
func (s *Server) adminOnly(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if s.admin == "" || !crypto.SecureEqualString(bearerToken(r), s.admin) {
			writeErr(w, http.StatusUnauthorized, "invalid admin token", "bad_admin_token")
			return
		}
		next(w, r)
	}
}

// rateLimited applies per-IP rate limiting on the name endpoint.
func (s *Server) rateLimited(name string, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !s.rl.Allow(name, clientIP(r)) {
			writeErr(w, http.StatusTooManyRequests, "too many requests, try again later", "rate_limited")
			return
		}
		next(w, r)
	}
}

func clientIP(r *http.Request) string {
	// Trust X-Forwarded-For only when the immediate peer is a loopback proxy.
	//
	// The server binds to 0.0.0.0 by default, so "the peer is on a private
	// network" is NOT a trust signal: any client on the LAN could then spoof
	// the header and bypass the rate limiter completely. Loopback is the only
	// case where the peer is necessarily the local reverse proxy.
	if isLoopbackPeer(r.RemoteAddr) {
		if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
			return strings.TrimSpace(strings.Split(xff, ",")[0])
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// isLoopbackPeer reports whether the immediate connection comes from the
// loopback interface (i.e. a reverse proxy running on this same host).
// IPv6 zone identifiers are stripped before parsing.
func isLoopbackPeer(remoteAddr string) bool {
	host, _, err := net.SplitHostPort(remoteAddr)
	if err != nil {
		host = remoteAddr
	}
	if i := strings.IndexByte(host, '%'); i >= 0 {
		host = host[:i] // strip IPv6 zone
	}
	ip := net.ParseIP(host)
	if ip == nil {
		return false
	}
	return ip.IsLoopback()
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(code int) {
	w.status = code
	w.ResponseWriter.WriteHeader(code)
}
