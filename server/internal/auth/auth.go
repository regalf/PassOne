package auth

import (
	"passone/internal/crypto"
	"passone/internal/store"
)

// VerifyAuthHash confronta in tempo costante l'hash inviato dal client con quello salvato.
func VerifyAuthHash(u *store.User, sent []byte) bool {
	if u.AuthHash == nil || sent == nil {
		return false
	}
	return crypto.SecureEqual(u.AuthHash, sent)
}

// VerifyRecoveryHash confronta in tempo costante l'hash della recovery key inviato.
func VerifyRecoveryHash(u *store.User, sent []byte) bool {
	if u.RecoveryHash == nil || sent == nil {
		return false
	}
	return crypto.SecureEqual(u.RecoveryHash, sent)
}

// VerifyInviteToken confronta in tempo costante l'invite token inviato.
func VerifyInviteToken(u *store.User, token string) bool {
	if u.InviteTokenHash == nil || token == "" {
		return false
	}
	return crypto.SecureEqual(u.InviteTokenHash, crypto.SHA256([]byte(token)))
}
