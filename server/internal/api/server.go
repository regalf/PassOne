package api

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"passone/internal/config"
	"passone/internal/store"
	"passone/internal/tlscert"
)

const rfc3339 = time.RFC3339

func timeNow() time.Time { return time.Now().UTC() }

var errUsernameTaken = errors.New("username already in use")

// Server is the PassOne HTTP server.
type Server struct {
	cfg   *config.Config
	store *store.Store
	rl    *RateLimiter
	log   *slog.Logger
	admin string // effective admin token (config or generated)
}

// New creates a new Server.
func New(cfg *config.Config, st *store.Store, log *slog.Logger) *Server {
	admin := cfg.AdminToken
	if admin == "" {
		admin = "admin_" + randomHex(32)
	}
	return &Server{
		cfg:   cfg,
		store: st,
		rl:    NewRateLimiter(20, time.Minute),
		log:   log,
		admin: admin,
	}
}

// TLSPublic returns the transport mode the server presents to clients
// and, for "selfsigned", the SPKI fingerprint to pair with. The fingerprint
// is read from the current certificate so it always matches the file on
// disk (also after `passone tls rotate` without a server restart).
func (s *Server) TLSPublic() (mode, fingerprint string) {
	switch s.cfg.TLSMode {
	case config.TLSModeSelfSigned:
		if info, err := tlscert.Inform(certPath(s.cfg)); err == nil {
			return config.TLSModeSelfSigned, info.Fingerprint.String()
		}
		return config.TLSModeSelfSigned, ""
	case config.TLSModeCustom:
		return config.TLSModeCustom, ""
	default:
		return config.TLSModeNone, ""
	}
}

// certPath returns the certificate path for the current config.
func certPath(cfg *config.Config) string {
	if cfg.TLSCert != "" {
		return cfg.TLSCert
	}
	return "tls-cert.pem"
}

// AdminToken returns the effective admin token (useful for the CLI to print it on first startup).
func (s *Server) AdminToken() string { return s.admin }

// Routes builds the router with all middleware.
func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("POST /api/v1/auth/prelogin", s.logged(s.rateLimited("prelogin", s.handlePrelogin)))
	mux.HandleFunc("POST /api/v1/auth/setup", s.logged(s.rateLimited("setup", s.handleSetup)))
	mux.HandleFunc("POST /api/v1/auth/login", s.logged(s.rateLimited("login", s.handleLogin)))
	mux.HandleFunc("POST /api/v1/auth/logout", s.logged(s.authed(s.handleLogout)))
	mux.HandleFunc("POST /api/v1/auth/logout-all", s.logged(s.authed(s.handleLogoutAll)))
	mux.HandleFunc("POST /api/v1/auth/change-password", s.logged(s.authed(s.handleChangePassword)))
	mux.HandleFunc("POST /api/v1/auth/recover", s.logged(s.rateLimited("recover", s.handleRecover)))
	mux.HandleFunc("POST /api/v1/auth/recover-payload", s.logged(s.rateLimited("recover", s.handleRecoverPayload)))

	mux.HandleFunc("GET /api/v1/vault", s.logged(s.authed(s.handleVaultGet)))
	mux.HandleFunc("PUT /api/v1/vault", s.logged(s.authed(s.handleVaultPut)))

	mux.HandleFunc("GET /api/v1/admin/users", s.logged(s.adminOnly(s.handleAdminListUsers)))
	mux.HandleFunc("POST /api/v1/admin/users", s.logged(s.adminOnly(s.handleAdminCreateUser)))
	mux.HandleFunc("DELETE /api/v1/admin/users/{id}", s.logged(s.adminOnly(s.handleAdminDeleteUser)))
	mux.HandleFunc("POST /api/v1/admin/users/{id}/reset-invite", s.logged(s.adminOnly(s.handleAdminResetInvite)))
	mux.HandleFunc("GET /api/v1/admin/pairing", s.logged(s.adminOnly(s.handleAdminPairing)))

	mux.HandleFunc("GET /health", s.handleHealth)

	return secureHeaders(limitBody(mux))
}

// ---------- response helpers ----------

type apiError struct {
	Error string `json:"error"`
	Code  string `json:"code,omitempty"`
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, status int, msg, code string) {
	writeJSON(w, status, apiError{Error: msg, Code: code})
}

func decodeJSON(w http.ResponseWriter, r *http.Request, v any) error {
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 10<<20))
	return dec.Decode(v)
}

func bearerToken(r *http.Request) string {
	h := r.Header.Get("Authorization")
	return strings.TrimPrefix(h, "Bearer ")
}

// ---------- base handlers ----------

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	status := "ok"
	if err := s.store.Ping(); err != nil {
		status = "degraded"
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": status, "time": time.Now().UTC().Format(time.RFC3339)})
}

func httpStatus(err error) (int, string) {
	switch {
	case errors.Is(err, store.ErrNotFound):
		return http.StatusNotFound, "resource not found"
	case errors.Is(err, store.ErrConflict):
		return http.StatusConflict, "revision conflict"
	default:
		return http.StatusInternalServerError, "internal error"
	}
}
