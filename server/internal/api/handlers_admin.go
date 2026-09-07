package api

import (
	"encoding/base64"
	"net/http"
	"strconv"
	"strings"

	"github.com/skip2/go-qrcode"
	"passone/internal/config"
	"passone/internal/store"
)

type adminUserResponse struct {
	ID            int64  `json:"id"`
	Username      string `json:"username"`
	Status        string `json:"status"`
	VaultRevision int64  `json:"vault_revision"`
	CreatedAt     string `json:"created_at"`
	UpdatedAt     string `json:"updated_at"`
}

// pairingInfoResponse is the payload of GET /api/v1/admin/pairing. It lets an
// admin display the pairing material clients need when the server presents a
// self-signed certificate: the SPKI fingerprint and a scannable QR encoding
// the passone://pair/<fingerprint> URI.
type pairingInfoResponse struct {
	TLSMode     string `json:"tls_mode"`
	Fingerprint string `json:"fingerprint,omitempty"`
	PairURL     string `json:"pair_url,omitempty"`
	QRDataURL   string `json:"qr,omitempty"`
}

func (s *Server) handleAdminPairing(w http.ResponseWriter, r *http.Request) {
	mode, fp := s.TLSPublic()
	out := pairingInfoResponse{TLSMode: mode}
	if mode == config.TLSModeSelfSigned && fp != "" {
		uri := "passone://pair/" + fp
		out.Fingerprint = fp
		out.PairURL = uri
		if qr, err := qrDataURL(uri); err == nil {
			out.QRDataURL = qr
		}
	}
	writeJSON(w, http.StatusOK, out)
}

// qrDataURL renders v as a QR code PNG and returns it as a data: URL, so the
// admin web UI can embed it directly in an <img>.
func qrDataURL(v string) (string, error) {
	code, err := qrcode.New(v, qrcode.Medium)
	if err != nil {
		return "", err
	}
	png, err := code.PNG(256)
	if err != nil {
		return "", err
	}
	return "data:image/png;base64," + base64.StdEncoding.EncodeToString(png), nil
}

func (s *Server) handleAdminListUsers(w http.ResponseWriter, r *http.Request) {
	users, err := s.store.ListUsers()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "internal error", "internal")
		return
	}
	out := make([]adminUserResponse, 0, len(users))
	for _, u := range users {
		out = append(out, adminUserResponse{
			ID:            u.ID,
			Username:      u.Username,
			Status:        u.Status,
			VaultRevision: u.Revision,
			CreatedAt:     u.Created.Format(rfc3339),
			UpdatedAt:     u.Updated.Format(rfc3339),
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{"users": out})
}

type adminCreateUserRequest struct {
	Username string `json:"username"`
}

func (s *Server) handleAdminCreateUser(w http.ResponseWriter, r *http.Request) {
	var req adminCreateUserRequest
	if err := decodeJSON(w, r, &req); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid body", "bad_request")
		return
	}
	username := strings.TrimSpace(req.Username)
	if username == "" || len(username) > 128 {
		writeErr(w, http.StatusBadRequest, "invalid username", "bad_username")
		return
	}
	token, err := s.store.CreatePendingUser(username)
	if err != nil {
		writeErr(w, http.StatusConflict, "username already in use", "username_taken")
		return
	}
	u, err := s.store.GetUserByUsername(username)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "internal error", "internal")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{
		"user": adminUserResponse{
			ID:        u.ID,
			Username:  u.Username,
			Status:    u.Status,
			CreatedAt: u.CreatedAt.Format(rfc3339),
			UpdatedAt: u.UpdatedAt.Format(rfc3339),
		},
		"invite_token": token,
	})
}

func (s *Server) handleAdminDeleteUser(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		writeErr(w, http.StatusBadRequest, "invalid id", "bad_id")
		return
	}
	if err := s.store.DeleteUser(id); err != nil {
		status, msg := httpStatus(err)
		writeErr(w, status, msg, "delete")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleAdminResetInvite(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		writeErr(w, http.StatusBadRequest, "invalid id", "bad_id")
		return
	}
	u, err := s.store.GetUserByID(id)
	if err != nil {
		status, msg := httpStatus(err)
		writeErr(w, status, msg, "not_found")
		return
	}
	if u.Status != store.StatusPending {
		writeErr(w, http.StatusConflict, "user is not in pending state", "not_pending")
		return
	}
	token, err := s.store.ResetInviteToken(u.Username)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "internal error", "internal")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"invite_token": token})
}
