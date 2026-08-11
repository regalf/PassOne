package api

import (
	"net/http"

	"passone/internal/crypto"
	"passone/internal/store"
)

// vaultPayload is the wire representation of the vault (encrypted blob + materials).
type vaultPayload struct {
	VaultBlobB64            string       `json:"vault_blob_b64"`
	VaultNonceB64           string       `json:"vault_nonce_b64"`
	VaultKeyWrappedB64      string       `json:"vault_key_wrapped_b64"`
	VaultKeyWrappedRecovB64 string       `json:"vault_key_wrapped_recov_b64"`
	RecoveryEnabled         bool         `json:"recovery_enabled"`
	SaltB64                 string       `json:"salt_b64"`
	KDF                     kdfInput     `json:"kdf"`
	VaultRevision           int64        `json:"vault_revision"`
}

func (s *Server) handleVaultGet(w http.ResponseWriter, r *http.Request) {
	u := s.userFrom(r.Context())
	payload := vaultPayload{
		VaultBlobB64:      crypto.EncodeBase64(u.VaultBlob),
		VaultNonceB64:     crypto.EncodeBase64(u.VaultNonce),
		VaultKeyWrappedB64: crypto.EncodeBase64(u.VaultKeyWrapped),
		RecoveryEnabled:   u.RecoveryHash != nil,
		SaltB64:           crypto.EncodeBase64(u.Salt),
		KDF: kdfInput{
			Algorithm: u.KDFAlgorithm,
			Params:    u.KDFParams,
		},
		VaultRevision: u.VaultRevision,
	}
	if u.VaultKeyWrappedRecov != nil {
		payload.VaultKeyWrappedRecovB64 = crypto.EncodeBase64(u.VaultKeyWrappedRecov)
	}
	writeJSON(w, http.StatusOK, payload)
}

type vaultPutRequest struct {
	BaseRevision              int64  `json:"base_revision"`
	VaultBlobB64              string `json:"vault_blob_b64"`
	VaultNonceB64             string `json:"vault_nonce_b64"`
	VaultKeyWrappedB64        string `json:"vault_key_wrapped_b64"`
	VaultKeyWrappedRecovB64   string `json:"vault_key_wrapped_recov_b64"`
}

func (s *Server) handleVaultPut(w http.ResponseWriter, r *http.Request) {
	var req vaultPutRequest
	if err := decodeJSON(w, r, &req); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid body", "bad_request")
		return
	}
	u := s.userFrom(r.Context())
	blob, err := crypto.DecodeBase64(req.VaultBlobB64)
	if err != nil || len(blob) == 0 {
		writeErr(w, http.StatusBadRequest, "invalid vault blob", "bad_blob")
		return
	}
	nonce, err := crypto.DecodeBase64(req.VaultNonceB64)
	if err != nil || len(nonce) == 0 {
		writeErr(w, http.StatusBadRequest, "invalid nonce", "bad_nonce")
		return
	}
	var wrapped, wrappedRecov []byte
	if req.VaultKeyWrappedB64 != "" {
		wrapped, err = crypto.DecodeBase64(req.VaultKeyWrappedB64)
		if err != nil {
			writeErr(w, http.StatusBadRequest, "invalid wrapped vault_key", "bad_wrapped_key")
			return
		}
	}
	if req.VaultKeyWrappedRecovB64 != "" {
		wrappedRecov, err = crypto.DecodeBase64(req.VaultKeyWrappedRecovB64)
		if err != nil {
			writeErr(w, http.StatusBadRequest, "invalid wrapped recovery vault_key", "bad_wrapped_recov")
			return
		}
	}
	newRev, err := s.store.UpdateVault(u.ID, req.BaseRevision, blob, nonce, wrapped, wrappedRecov)
	if err != nil {
		if err == store.ErrConflict {
			writeJSON(w, http.StatusConflict, map[string]any{
				"error":           "revision conflict",
				"code":            "revision_conflict",
				"current_revision": u.VaultRevision,
			})
			return
		}
		writeErr(w, http.StatusInternalServerError, "internal error", "internal")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"vault_revision": newRev})
}
