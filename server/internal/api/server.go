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
)

const rfc3339 = time.RFC3339

func timeNow() time.Time { return time.Now().UTC() }

var errUsernameTaken = errors.New("username già in uso")

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
		admin = "admin_" + randomHex(24)
	}
	return &Server{
		cfg:   cfg,
		store: st,
		rl:    NewRateLimiter(20, time.Minute),
		log:   log,
		admin: admin,
	}
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

	mux.HandleFunc("GET /health", s.handleHealth)

	return mux
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
		return http.StatusNotFound, "risorsa non trovata"
	case errors.Is(err, store.ErrConflict):
		return http.StatusConflict, "conflitto di revisione"
	default:
		return http.StatusInternalServerError, "errore interno"
	}
}
