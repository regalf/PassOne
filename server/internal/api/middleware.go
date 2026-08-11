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

const ctxUserKey ctxKey = 0

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
			writeErr(w, http.StatusUnauthorized, "sessione mancante", "no_session")
			return
		}
		u, err := s.store.GetUserBySessionToken(token)
		if err != nil {
			writeErr(w, http.StatusUnauthorized, "sessione non valida o scaduta", "bad_session")
			return
		}
		if u.Status != store.StatusActive {
			writeErr(w, http.StatusForbidden, "account non attivo", "inactive")
			return
		}
		next(w, r.WithContext(context.WithValue(r.Context(), ctxUserKey, u)))
	}
}

// adminOnly requires the configured admin token.
func (s *Server) adminOnly(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if s.admin == "" || !crypto.SecureEqualString(bearerToken(r), s.admin) {
			writeErr(w, http.StatusUnauthorized, "token admin non valido", "bad_admin_token")
			return
		}
		next(w, r)
	}
}

// rateLimited applies per-IP rate limiting on the name endpoint.
func (s *Server) rateLimited(name string, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !s.rl.Allow(clientIP(r)) {
			writeErr(w, http.StatusTooManyRequests, "troppe richieste, riprova più tardi", "rate_limited")
			return
		}
		next(w, r)
	}
}

func clientIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		return strings.TrimSpace(strings.Split(xff, ",")[0])
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(code int) {
	w.status = code
	w.ResponseWriter.WriteHeader(code)
}
