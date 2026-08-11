package auth

import (
	"passone/internal/crypto"
	"passone/internal/store"
)

// VerifyAuthHash compares in constant time the hash sent by the client with the stored one.
func VerifyAuthHash(u *store.User, sent []byte) bool {
	if u.AuthHash == nil || sent == nil {
		return false
	}
	return crypto.SecureEqual(u.AuthHash, sent)
}

// VerifyRecoveryHash compares in constant time the recovery key hash sent by the client.
func VerifyRecoveryHash(u *store.User, sent []byte) bool {
	if u.RecoveryHash == nil || sent == nil {
		return false
	}
	return crypto.SecureEqual(u.RecoveryHash, sent)
}

// VerifyInviteToken compares in constant time the invite token sent by the client.
func VerifyInviteToken(u *store.User, token string) bool {
	if u.InviteTokenHash == nil || token == "" {
		return false
	}
	return crypto.SecureEqual(u.InviteTokenHash, crypto.SHA256([]byte(token)))
}
