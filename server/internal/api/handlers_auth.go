package api

import (
	"net/http"
	"strings"

	"passone/internal/auth"
	"passone/internal/crypto"
	"passone/internal/store"
)

type kdfInput struct {
	Algorithm string       `json:"algorithm"`
	Params    store.KDFParams `json:"params"`
}

type setupRequest struct {
	Username                  string       `json:"username"`
	InviteToken               string       `json:"invite_token"`
	AuthHashB64               string       `json:"auth_hash_b64"`
	SaltB64                   string       `json:"salt_b64"`
	KDF                       kdfInput     `json:"kdf"`
	VaultKeyWrappedB64        string       `json:"vault_key_wrapped_b64"`
	VaultKeyWrappedRecovB64   string       `json:"vault_key_wrapped_recov_b64"`
	RecoveryHashB64           string       `json:"recovery_hash_b64"`
	VaultBlobB64              string       `json:"vault_blob_b64"`
	VaultNonceB64             string       `json:"vault_nonce_b64"`
	DeviceName                string       `json:"device_name"`
}

// validateKDF verifica che i parametri KDF siano ragionevoli (anti-DoS).
// Per argon2id m è in KiB (il limite di config è in MiB); pbkdf2 non ha m/p.
func (s *Server) validateKDF(k kdfInput) bool {
	switch k.Algorithm {
	case "argon2id":
		if k.Params.MemoryKiB == 0 || k.Params.Iterations == 0 || k.Params.Parallelism == 0 {
			return false
		}
		if int(k.Params.MemoryKiB) > s.cfg.MaxKDFMemoryMB*1024 {
			return false
		}
		if k.Params.Parallelism > 16 {
			return false
		}
	case "pbkdf2-sha256":
		if k.Params.Iterations == 0 {
			return false
		}
	default:
		return false
	}
	if k.Params.Iterations > uint32(s.cfg.MaxKDFIterations) {
		return false
	}
	return true
}

type sessionResponse struct {
	Token     string `json:"token"`
	ExpiresAt string `json:"expires_at"`
	User      userPublic `json:"user"`
}

type userPublic struct {
	ID              int64  `json:"id"`
	Username        string `json:"username"`
	Status          string `json:"status"`
	VaultRevision   int64  `json:"vault_revision"`
	RecoveryEnabled bool   `json:"recovery_enabled"`
	KDFAlgorithm    string `json:"kdf_algorithm"`
}

func toPublic(u *store.User) userPublic {
	return userPublic{
		ID:              u.ID,
		Username:        u.Username,
		Status:          u.Status,
		VaultRevision:   u.VaultRevision,
		RecoveryEnabled: u.RecoveryHash != nil,
		KDFAlgorithm:    u.KDFAlgorithm,
	}
}

// handleSetup registra un nuovo utente (direttamente se consentito) o attiva un utente pending.
func (s *Server) handleSetup(w http.ResponseWriter, r *http.Request) {
	var req setupRequest
	if err := decodeJSON(w, r, &req); err != nil {
		writeErr(w, http.StatusBadRequest, "body non valido", "bad_request")
		return
	}
	username := strings.TrimSpace(req.Username)
	if username == "" || len(username) > 128 {
		writeErr(w, http.StatusBadRequest, "username non valido", "bad_username")
		return
	}
	if !s.validateKDF(req.KDF) {
		writeErr(w, http.StatusBadRequest, "parametri KDF non validi", "bad_kdf")
		return
	}
	authHash, err := crypto.DecodeBase64(req.AuthHashB64)
	if err != nil || len(authHash) == 0 {
		writeErr(w, http.StatusBadRequest, "auth_hash non valido", "bad_auth_hash")
		return
	}
	salt, err := crypto.DecodeBase64(req.SaltB64)
	if err != nil || len(salt) == 0 {
		writeErr(w, http.StatusBadRequest, "salt non valido", "bad_salt")
		return
	}
	wrapped, err := crypto.DecodeBase64(req.VaultKeyWrappedB64)
	if err != nil || len(wrapped) == 0 {
		writeErr(w, http.StatusBadRequest, "vault_key avvolta non valida", "bad_wrapped_key")
		return
	}
	blob, err := crypto.DecodeBase64(req.VaultBlobB64)
	if err != nil || len(blob) == 0 {
		writeErr(w, http.StatusBadRequest, "vault blob non valido", "bad_blob")
		return
	}
	nonce, err := crypto.DecodeBase64(req.VaultNonceB64)
	if err != nil || len(nonce) == 0 {
		writeErr(w, http.StatusBadRequest, "nonce non valido", "bad_nonce")
		return
	}

	var recoveryHash []byte
	var wrappedRecov []byte
	if req.RecoveryHashB64 != "" {
		recoveryHash, err = crypto.DecodeBase64(req.RecoveryHashB64)
		if err != nil {
			writeErr(w, http.StatusBadRequest, "recovery hash non valido", "bad_recovery_hash")
			return
		}
		wrappedRecov, err = crypto.DecodeBase64(req.VaultKeyWrappedRecovB64)
		if err != nil || len(wrappedRecov) == 0 {
			writeErr(w, http.StatusBadRequest, "vault_key recovery avvolta mancante", "bad_wrapped_recov")
			return
		}
	}

	u := &store.User{
		Username:             username,
		Status:               store.StatusActive,
		AuthHash:             authHash,
		Salt:                 salt,
		KDFAlgorithm:         req.KDF.Algorithm,
		KDFParams:            req.KDF.Params,
		VaultKeyWrapped:      wrapped,
		VaultKeyWrappedRecov: wrappedRecov,
		RecoveryHash:         recoveryHash,
		VaultBlob:            blob,
		VaultNonce:           nonce,
		VaultRevision:        1,
	}

	if req.InviteToken != "" {
		// Flusso admin: l'utente deve esistere come pending.
		existing, err := s.store.GetUserByUsername(username)
		if err != nil || existing.Status != store.StatusPending {
			writeErr(w, http.StatusConflict, "account non in attesa di configurazione", "not_pending")
			return
		}
		if !auth.VerifyInviteToken(existing, req.InviteToken) {
			writeErr(w, http.StatusForbidden, "invite token non valido", "bad_invite")
			return
		}
		u.ID = existing.ID
		if err := s.store.ActivateUser(u, req.KDF.Params); err != nil {
			status, msg := httpStatus(err)
			writeErr(w, status, msg, "activate")
			return
		}
	} else {
		if !s.cfg.AllowRegistration {
			writeErr(w, http.StatusForbidden, "registrazione disabilitata", "registration_disabled")
			return
		}
		u.ID, err = s.createUser(username, u)
		if err != nil {
			writeErr(w, http.StatusConflict, "username già in uso", "username_taken")
			return
		}
	}

	s.completeSession(w, u, req.DeviceName)
}

func (s *Server) createUser(username string, u *store.User) (int64, error) {
	if _, err := s.store.GetUserByUsername(username); err == nil {
		return 0, errUsernameTaken
	} else if err != store.ErrNotFound {
		return 0, err
	}
	return s.store.InsertUser(u)
}

type preloginRequest struct {
	Username string `json:"username"`
}

// handlePrelogin restituisce salt + parametri KDF per derivare la chiave prima del login.
// Per username sconosciuti risponde con dati casuali (anti-enumeration) e status "unknown".
func (s *Server) handlePrelogin(w http.ResponseWriter, r *http.Request) {
	var req preloginRequest
	if err := decodeJSON(w, r, &req); err != nil {
		writeErr(w, http.StatusBadRequest, "body non valido", "bad_request")
		return
	}
	username := strings.TrimSpace(req.Username)
	resp := map[string]any{
		"username": username,
		"status":   "unknown",
		"salt_b64": crypto.EncodeBase64(mustRandom(16)),
		"kdf": kdfInput{
			Algorithm: "argon2id",
			Params:    store.KDFParams{MemoryKiB: 65536, Iterations: 3, Parallelism: 4},
		},
	}
	u, err := s.store.GetUserByUsername(username)
	if err == nil {
		resp["status"] = u.Status
		if u.Salt != nil {
			resp["salt_b64"] = crypto.EncodeBase64(u.Salt)
		}
		resp["kdf"] = kdfInput{Algorithm: u.KDFAlgorithm, Params: u.KDFParams}
	}
	writeJSON(w, http.StatusOK, resp)
}

type loginRequest struct {
	Username   string `json:"username"`
	AuthHashB64 string `json:"auth_hash_b64"`
	DeviceName string `json:"device_name"`
}

func (s *Server) handleLogin(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if err := decodeJSON(w, r, &req); err != nil {
		writeErr(w, http.StatusBadRequest, "body non valido", "bad_request")
		return
	}
	u, err := s.store.GetUserByUsername(strings.TrimSpace(req.Username))
	if err != nil {
		writeErr(w, http.StatusUnauthorized, "credenziali non valide", "bad_credentials")
		return
	}
	if u.Status == store.StatusPending {
		writeErr(w, http.StatusConflict, "account in attesa di configurazione", "pending")
		return
	}
	if u.Status != store.StatusActive {
		writeErr(w, http.StatusForbidden, "account disabilitato", "disabled")
		return
	}
	authHash, err := crypto.DecodeBase64(req.AuthHashB64)
	if err != nil || !auth.VerifyAuthHash(u, authHash) {
		writeErr(w, http.StatusUnauthorized, "credenziali non valide", "bad_credentials")
		return
	}
	_ = s.store.UpdateLastLogin(u.ID)
	s.completeSession(w, u, req.DeviceName)
}

func (s *Server) handleLogout(w http.ResponseWriter, r *http.Request) {
	_ = s.store.DeleteSession(bearerToken(r))
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleLogoutAll(w http.ResponseWriter, r *http.Request) {
	u := s.userFrom(r.Context())
	if err := s.store.DeleteAllSessions(u.ID); err != nil {
		writeErr(w, http.StatusInternalServerError, "errore interno", "internal")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// completeSession crea una sessione e restituisce la risposta standard.
func (s *Server) completeSession(w http.ResponseWriter, u *store.User, deviceName string) {
	token, err := s.store.CreateSession(u.ID, deviceName, s.cfg.SessionTTL)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "errore interno", "internal")
		return
	}
	writeJSON(w, http.StatusOK, sessionResponse{
		Token:     token,
		ExpiresAt: timeNow().Add(s.cfg.SessionTTL).Format(rfc3339),
		User:      toPublic(u),
	})
}

func mustRandom(n int) []byte {
	b, _ := crypto.RandomBytes(n)
	return b
}
