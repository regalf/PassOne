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

// secureHeaders sets hardening headers on every response.
func secureHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Referrer-Policy", "no-referrer")
		// HSTS only makes sense over HTTPS (direct TLS or behind a proxy that
		// forwards the scheme). Setting it on plain HTTP would be harmful.
		if r.TLS != nil || strings.EqualFold(r.Header.Get("X-Forwarded-Proto"), "https") {
			w.Header().Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		}
		next.ServeHTTP(w, r)
	})
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
		if !s.rl.Allow(clientIP(r)) {
			writeErr(w, http.StatusTooManyRequests, "too many requests, try again later", "rate_limited")
			return
		}
		next(w, r)
	}
}

func clientIP(r *http.Request) string {
	// Trust X-Forwarded-For only when the immediate peer is a local reverse
	// proxy (loopback/private network). Otherwise an attacker could spoof
	// arbitrary IPs to bypass rate limiting.
	if isPrivatePeer(r.RemoteAddr) {
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

// isPrivatePeer reports whether the immediate connection comes from loopback
// or a private/unique-local address (i.e. a reverse proxy on the same host or
// LAN). IPv6 zone identifiers are stripped before parsing.
func isPrivatePeer(remoteAddr string) bool {
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
	return ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast()
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(code int) {
	w.status = code
	w.ResponseWriter.WriteHeader(code)
}
