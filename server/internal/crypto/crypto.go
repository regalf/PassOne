package crypto

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"fmt"
	"math/big"
)

// SHA256 computes the SHA-256 hash of b.
func SHA256(b []byte) []byte {
	h := sha256.Sum256(b)
	return h[:]
}

// SecureEqual compares two byte slices in constant time.
func SecureEqual(a, b []byte) bool {
	return subtle.ConstantTimeCompare(a, b) == 1
}

// SecureEqualString compares two strings in constant time.
func SecureEqualString(a, b string) bool {
	return SecureEqual([]byte(a), []byte(b))
}

// RandomBytes generates n random bytes from crypto/rand.
func RandomBytes(n int) ([]byte, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return nil, fmt.Errorf("crypto/rand: %w", err)
	}
	return b, nil
}

// RandomHex generates a random hex string of n bytes.
func RandomHex(n int) (string, error) {
	b, err := RandomBytes(n)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%x", b), nil
}

// EncodeBase64 encodes using standard base64.
func EncodeBase64(b []byte) string {
	return base64.StdEncoding.EncodeToString(b)
}

// DecodeBase64 decodes standard base64.
func DecodeBase64(s string) ([]byte, error) {
	return base64.StdEncoding.DecodeString(s)
}

// RandomInt generates a random integer in [0, n).
func RandomInt(n int) (int, error) {
	v, err := rand.Int(rand.Reader, big.NewInt(int64(n)))
	if err != nil {
		return 0, err
	}
	return int(v.Int64()), nil
}
