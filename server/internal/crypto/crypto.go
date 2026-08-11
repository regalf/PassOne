package crypto

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"fmt"
	"math/big"
)

// SHA256 calcola l'hash SHA-256 di b.
func SHA256(b []byte) []byte {
	h := sha256.Sum256(b)
	return h[:]
}

// SecureEqual confronta due byte slice in tempo costante.
func SecureEqual(a, b []byte) bool {
	return subtle.ConstantTimeCompare(a, b) == 1
}

// SecureEqualString confronta due stringhe in tempo costante.
func SecureEqualString(a, b string) bool {
	return SecureEqual([]byte(a), []byte(b))
}

// RandomBytes genera n byte casuali da crypto/rand.
func RandomBytes(n int) ([]byte, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return nil, fmt.Errorf("crypto/rand: %w", err)
	}
	return b, nil
}

// RandomHex genera una stringa esadecimale casuale di n byte.
func RandomHex(n int) (string, error) {
	b, err := RandomBytes(n)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%x", b), nil
}

// EncodeBase64 codifica in base64 standard.
func EncodeBase64(b []byte) string {
	return base64.StdEncoding.EncodeToString(b)
}

// DecodeBase64 decodifica base64 standard.
func DecodeBase64(s string) ([]byte, error) {
	return base64.StdEncoding.DecodeString(s)
}

// RandomInt genera un intero casuale in [0, n).
func RandomInt(n int) (int, error) {
	v, err := rand.Int(rand.Reader, big.NewInt(int64(n)))
	if err != nil {
		return 0, err
	}
	return int(v.Int64()), nil
}
