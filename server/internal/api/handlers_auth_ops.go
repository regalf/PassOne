package api

import (
	"net/http"
	"strings"

	"passone/internal/auth"
	"passone/internal/crypto"
	"passone/internal/store"
)

// authMaterialInput raccoglie i materiali crittografici inviati dal client.
type authMaterialInput struct {
	AuthHashB64             string    `json:"auth_hash_b64"`
	SaltB64                 string    `json:"salt_b64"`
	KDF                     kdfInput  `json:"kdf"`
	VaultKeyWrappedB64      string    `json:"vault_key_wrapped_b64"`
	VaultKeyWrappedRecovB64 string    `json:"vault_key_wrapped_recov_b64"`
	RecoveryHashB64         string    `json:"recovery_hash_b64"`
}

// parseAuthMaterial valida e decodifica i materiali; recoveryHash/vaultKeyWrappedRecov
// sono nil se l'utente non usa la recovery key (e in quel caso vengono azzerati).
func (s *Server) parseAuthMaterial(req authMaterialInput) (*store.User, string) {
	if !s.validateKDF(req.KDF) {
		return nil, "bad_kdf"
	}
	authHash, err := crypto.DecodeBase64(req.AuthHashB64)
	if err != nil || len(authHash) == 0 {
		return nil, "bad_auth_hash"
	}
	salt, err := crypto.DecodeBase64(req.SaltB64)
	if err != nil || len(salt) == 0 {
		return nil, "bad_salt"
	}
	wrapped, err := crypto.DecodeBase64(req.VaultKeyWrappedB64)
	if err != nil || len(wrapped) == 0 {
		return nil, "bad_wrapped_key"
	}
	var recoveryHash []byte
	var wrappedRecov []byte
	if req.RecoveryHashB64 != "" {
		recoveryHash, err = crypto.DecodeBase64(req.RecoveryHashB64)
		if err != nil {
			return nil, "bad_recovery_hash"
		}
		wrappedRecov, err = crypto.DecodeBase64(req.VaultKeyWrappedRecovB64)
		if err != nil || len(wrappedRecov) == 0 {
			return nil, "bad_wrapped_recov"
		}
	}
	return &store.User{
		AuthHash:             authHash,
		Salt:                 salt,
		KDFAlgorithm:         req.KDF.Algorithm,
		KDFParams:            req.KDF.Params,
		VaultKeyWrapped:      wrapped,
		VaultKeyWrappedRecov: wrappedRecov,
		RecoveryHash:         recoveryHash,
	}, ""
}

type changePasswordRequest struct {
	OldAuthHashB64 string            `json:"old_auth_hash_b64"`
	New            authMaterialInput `json:"new"`
}

func (s *Server) handleChangePassword(w http.ResponseWriter, r *http.Request) {
	var req changePasswordRequest
	if err := decodeJSON(w, r, &req); err != nil {
		writeErr(w, http.StatusBadRequest, "body non valido", "bad_request")
		return
	}
	u := s.userFrom(r.Context())
	oldHash, err := crypto.DecodeBase64(req.OldAuthHashB64)
	if err != nil || !auth.VerifyAuthHash(u, oldHash) {
		writeErr(w, http.StatusUnauthorized, "password attuale non valida", "bad_old_password")
		return
	}
	newMat, code := s.parseAuthMaterial(req.New)
	if code != "" {
		writeErr(w, http.StatusBadRequest, "materiali non validi", code)
		return
	}
	newMat.ID = u.ID
	if err := s.store.UpdateAuthMaterial(newMat, newMat.KDFParams, false); err != nil {
		writeErr(w, http.StatusInternalServerError, "errore interno", "internal")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

type recoverRequest struct {
	Username        string            `json:"username"`
	RecoveryHashB64 string            `json:"recovery_hash_b64"`
	New             authMaterialInput `json:"new"`
	DeviceName      string            `json:"device_name"`
}

// recoverPayloadRequest è la richiesta per scaricare il vault criptato con la recovery key.
type recoverPayloadRequest struct {
	Username        string `json:"username"`
	RecoveryHashB64 string `json:"recovery_hash_b64"`
}

// handleRecoverPayload verifica la recovery key e restituisce il vault criptato:
// il client usa questi dati per srotolare la vault_key e poi chiamare /auth/recover.
// Non modifica nulla: la key non viene bruciata qui.
func (s *Server) handleRecoverPayload(w http.ResponseWriter, r *http.Request) {
	var req recoverPayloadRequest
	if err := decodeJSON(w, r, &req); err != nil {
		writeErr(w, http.StatusBadRequest, "body non valido", "bad_request")
		return
	}
	u, err := s.store.GetUserByUsername(strings.TrimSpace(req.Username))
	if err != nil {
		writeErr(w, http.StatusUnauthorized, "recovery key non valida", "bad_recovery")
		return
	}
	recHash, err := crypto.DecodeBase64(req.RecoveryHashB64)
	if err != nil || !auth.VerifyRecoveryHash(u, recHash) {
		writeErr(w, http.StatusUnauthorized, "recovery key non valida", "bad_recovery")
		return
	}
	if u.VaultKeyWrappedRecov == nil {
		writeErr(w, http.StatusNotFound, "recovery key non attiva per questo account", "no_recovery")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"vault_blob_b64":              crypto.EncodeBase64(u.VaultBlob),
		"vault_nonce_b64":             crypto.EncodeBase64(u.VaultNonce),
		"vault_key_wrapped_b64":       crypto.EncodeBase64(u.VaultKeyWrapped),
		"vault_key_wrapped_recov_b64": crypto.EncodeBase64(u.VaultKeyWrappedRecov),
		"salt_b64":                    crypto.EncodeBase64(u.Salt),
		"kdf":                         kdfInput{Algorithm: u.KDFAlgorithm, Params: u.KDFParams},
		"vault_revision":              u.VaultRevision,
	})
}

func (s *Server) handleRecover(w http.ResponseWriter, r *http.Request) {
	var req recoverRequest
	if err := decodeJSON(w, r, &req); err != nil {
		writeErr(w, http.StatusBadRequest, "body non valido", "bad_request")
		return
	}
	u, err := s.store.GetUserByUsername(strings.TrimSpace(req.Username))
	if err != nil {
		writeErr(w, http.StatusUnauthorized, "recovery non valida", "bad_recovery")
		return
	}
	recHash, err := crypto.DecodeBase64(req.RecoveryHashB64)
	if err != nil || !auth.VerifyRecoveryHash(u, recHash) {
		writeErr(w, http.StatusUnauthorized, "recovery key non valida", "bad_recovery")
		return
	}
	newMat, code := s.parseAuthMaterial(req.New)
	if code != "" {
		writeErr(w, http.StatusBadRequest, "materiali non validi", code)
		return
	}
	newMat.ID = u.ID

	// Transazione atomica: sostituisce l'auth material, brucia la recovery key precedente
	// e revoca tutte le sessioni.
	if err := s.store.UpdateAuthMaterial(newMat, newMat.KDFParams, true); err != nil {
		writeErr(w, http.StatusInternalServerError, "errore interno", "internal")
		return
	}
	// Creo una sessione fresca per l'utente che ha appena recuperato l'accesso.
	fresh, err := s.store.GetUserByID(u.ID)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "errore interno", "internal")
		return
	}
	s.completeSession(w, fresh, req.DeviceName)
}
