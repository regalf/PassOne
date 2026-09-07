// Package tlscert manages the self-signed certificate used by the server
// in tls_mode "selfsigned".
//
// The trust anchor for clients is the SPKI fingerprint (SHA-256 of the
// encoded public key): it is stable across certificate renewals that reuse
// the same private key, so clients keep working when the certificate is
// re-signed, and only change when the key is rotated.
package tlscert

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"encoding/pem"
	"errors"
	"fmt"
	"math/big"
	"net"
	"os"
	"time"
)

// DefaultValidity is how long generated certificates are valid.
const DefaultValidity = 10 * 365 * 24 * time.Hour

// RenewWithin is how close to expiry (or past it) a certificate must be for
// it to be re-signed with the same private key on startup.
const RenewWithin = 90 * 24 * time.Hour

const certName = "passone"

// Fingerprint is the SPKI fingerprint of a server, formatted as a hex string,
// displayed to the user during pairing and pinned by the client.
type Fingerprint string

func (f Fingerprint) String() string { return string(f) }

// Info describes a generated certificate (for CLI/admin display).
type Info struct {
	Fingerprint Fingerprint
	Serial      string
	NotBefore   time.Time
	NotAfter    time.Time
	PublicKey   string
}

// Ensure makes sure a self-signed certificate and its private key exist on
// disk at certPath/keyPath:
//
//   - if the key is missing, a new key + certificate are generated;
//   - if only the certificate is missing, it is re-signed with the existing key;
//   - if the certificate is expired or within [RenewWithin] of expiry, it is
//     re-signed with the existing key (SPKI fingerprint stays stable);
//   - otherwise nothing is written.
//
// It returns a summary of what happened.
func Ensure(certPath, keyPath string, now time.Time) (*Info, error) {
	key, err := loadKey(keyPath)
	switch {
	case errors.Is(err, os.ErrNotExist):
		k, err := generateKey()
		if err != nil {
			return nil, err
		}
		key = k
		if err := saveKey(keyPath, key); err != nil {
			return nil, err
		}
	case err != nil:
		return nil, fmt.Errorf("loading private key: %w", err)
	}

	cert, err := loadCert(certPath)
	renew := false
	switch {
	case errors.Is(err, os.ErrNotExist):
		renew = true
	case err != nil:
		return nil, fmt.Errorf("loading certificate: %w", err)
	case cert.NotAfter.Before(now.Add(RenewWithin)):
		// Expired or about to expire: re-sign with the same key.
		renew = true
	}
	if renew {
		if err := saveCert(certPath, key, now); err != nil {
			return nil, err
		}
	}
	return Inform(certPath)
}

// Info returns certificate metadata. The certificate must exist.
func Inform(certPath string) (*Info, error) {
	cert, err := loadCert(certPath)
	if err != nil {
		return nil, err
	}
	pubDER, err := x509.MarshalPKIXPublicKey(cert.PublicKey)
	if err != nil {
		return nil, fmt.Errorf("encoding public key: %w", err)
	}
	fp := sha256.Sum256(pubDER)
	return &Info{
		Fingerprint: Fingerprint(hex.EncodeToString(fp[:])),
		Serial:      cert.SerialNumber.String(),
		NotBefore:   cert.NotBefore,
		NotAfter:    cert.NotAfter,
		PublicKey:   cert.PublicKeyAlgorithm.String(),
	}, nil
}

// Rotate regenerates the private key and re-signs a certificate with it:
// the fingerprint changes and every paired client must be paired again.
func Rotate(certPath, keyPath string, now time.Time) (*Info, error) {
	key, err := generateKey()
	if err != nil {
		return nil, err
	}
	if err := saveKey(keyPath, key); err != nil {
		return nil, err
	}
	if err := saveCert(certPath, key, now); err != nil {
		return nil, err
	}
	return Inform(certPath)
}

func generateKey() (*ecdsa.PrivateKey, error) {
	return ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
}

func loadKey(path string) (*ecdsa.PrivateKey, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	block, _ := pem.Decode(data)
	if block == nil || block.Type != "EC PRIVATE KEY" {
		return nil, errors.New("invalid private key file")
	}
	key, err := x509.ParseECPrivateKey(block.Bytes)
	if err != nil {
		return nil, err
	}
	return key, nil
}

func saveKey(path string, key *ecdsa.PrivateKey) error {
	der, err := x509.MarshalECPrivateKey(key)
	if err != nil {
		return err
	}
	data := pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: der})
	return writeFile0600(path, data)
}

func loadCert(path string) (*x509.Certificate, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	block, _ := pem.Decode(data)
	if block == nil || block.Type != "CERTIFICATE" {
		return nil, errors.New("invalid certificate file")
	}
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return nil, err
	}
	return cert, nil
}

func saveCert(path string, key *ecdsa.PrivateKey, now time.Time) error {
	notBefore := now.Add(-time.Hour)
	notAfter := now.Add(DefaultValidity)
	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return err
	}
	tmpl := &x509.Certificate{
		SerialNumber: serial,
		Subject: pkix.Name{
			CommonName: certName,
		},
		NotBefore:             notBefore,
		NotAfter:              notAfter,
		KeyUsage:              x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
		DNSNames:              []string{certName},
		IPAddresses:           []net.IP{net.ParseIP("127.0.0.1"), net.ParseIP("::1")},
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		return fmt.Errorf("creating certificate: %w", err)
	}
	data := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
	return writeFile0600(path, data)
}

func writeFile0600(path string, data []byte) error {
	return os.WriteFile(path, data, 0o600)
}
