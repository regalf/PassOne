package api

import (
	"net/http"
	"strconv"
	"strings"

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

func (s *Server) handleAdminListUsers(w http.ResponseWriter, r *http.Request) {
	users, err := s.store.ListUsers()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "errore interno", "internal")
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
		writeErr(w, http.StatusBadRequest, "body non valido", "bad_request")
		return
	}
	username := strings.TrimSpace(req.Username)
	if username == "" || len(username) > 128 {
		writeErr(w, http.StatusBadRequest, "username non valido", "bad_username")
		return
	}
	token, err := s.store.CreatePendingUser(username)
	if err != nil {
		writeErr(w, http.StatusConflict, "username già in uso", "username_taken")
		return
	}
	u, err := s.store.GetUserByUsername(username)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "errore interno", "internal")
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
		writeErr(w, http.StatusBadRequest, "id non valido", "bad_id")
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
		writeErr(w, http.StatusBadRequest, "id non valido", "bad_id")
		return
	}
	u, err := s.store.GetUserByID(id)
	if err != nil {
		status, msg := httpStatus(err)
		writeErr(w, status, msg, "not_found")
		return
	}
	if u.Status != store.StatusPending {
		writeErr(w, http.StatusConflict, "l'utente non è in stato pending", "not_pending")
		return
	}
	token, err := s.store.ResetInviteToken(u.Username)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "errore interno", "internal")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"invite_token": token})
}
