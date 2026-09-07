package tlscert

import (
	"crypto/ecdsa"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestEnsureCreatesCertAndKey(t *testing.T) {
	dir := t.TempDir()
	cert := filepath.Join(dir, "cert.pem")
	key := filepath.Join(dir, "key.pem")

	info, err := Ensure(cert, key, time.Now())
	if err != nil {
		t.Fatalf("Ensure: %v", err)
	}
	if info.Fingerprint == "" {
		t.Fatal("empty fingerprint")
	}
	if _, err := os.Stat(cert); err != nil {
		t.Fatalf("cert missing: %v", err)
	}
	if _, err := os.Stat(key); err != nil {
		t.Fatalf("key missing: %v", err)
	}
	// 0600 permissions on the key.
	st, _ := os.Stat(key)
	if st.Mode().Perm() != 0o600 {
		t.Fatalf("key perms = %o, want 600", st.Mode().Perm())
	}
}

func TestEnsureKeepsFingerprintAcrossRenewal(t *testing.T) {
	dir := t.TempDir()
	cert := filepath.Join(dir, "cert.pem")
	key := filepath.Join(dir, "key.pem")

	now := time.Now()
	info1, err := Ensure(cert, key, now)
	if err != nil {
		t.Fatalf("Ensure: %v", err)
	}
	// almost 10 years later: the cert is re-signed, the SPKI stays stable.
	later := now.Add(DefaultValidity - time.Hour)
	info2, err := Ensure(cert, key, later)
	if err != nil {
		t.Fatalf("Ensure renewal: %v", err)
	}
	if info1.Fingerprint != info2.Fingerprint {
		t.Fatalf("fingerprint changed across renewal:\n  %s\n  %s", info1.Fingerprint, info2.Fingerprint)
	}
	if !info2.NotAfter.After(info1.NotAfter) {
		t.Fatalf("certificate was not extended: %v -> %v", info1.NotAfter, info2.NotAfter)
	}
}

func TestEnsureIdempotentWithinValidity(t *testing.T) {
	dir := t.TempDir()
	cert := filepath.Join(dir, "cert.pem")
	key := filepath.Join(dir, "key.pem")

	now := time.Now()
	info1, err := Ensure(cert, key, now)
	if err != nil {
		t.Fatalf("Ensure: %v", err)
	}
	info2, err := Ensure(cert, key, now.Add(time.Hour))
	if err != nil {
		t.Fatalf("Ensure: %v", err)
	}
	if info1.Fingerprint != info2.Fingerprint {
		t.Fatal("fingerprint changed without renewal")
	}
}

func TestRotateChangesFingerprint(t *testing.T) {
	dir := t.TempDir()
	cert := filepath.Join(dir, "cert.pem")
	key := filepath.Join(dir, "key.pem")

	now := time.Now()
	info1, err := Ensure(cert, key, now)
	if err != nil {
		t.Fatalf("Ensure: %v", err)
	}
	info2, err := Rotate(cert, key, now)
	if err != nil {
		t.Fatalf("Rotate: %v", err)
	}
	if info1.Fingerprint == info2.Fingerprint {
		t.Fatal("rotate kept the same fingerprint (key was not regenerated)")
	}
}

func TestKeyMatchesCertificate(t *testing.T) {
	dir := t.TempDir()
	cert := filepath.Join(dir, "cert.pem")
	key := filepath.Join(dir, "key.pem")

	if _, err := Ensure(cert, key, time.Now()); err != nil {
		t.Fatalf("Ensure: %v", err)
	}
	k, err := loadKey(key)
	if err != nil {
		t.Fatalf("loadKey: %v", err)
	}
	c, err := loadCert(cert)
	if err != nil {
		t.Fatalf("loadCert: %v", err)
	}
	pub, ok := c.PublicKey.(*ecdsa.PublicKey)
	if !ok {
		t.Fatalf("unexpected public key type %T", c.PublicKey)
	}
	if !pub.Equal(k.Public()) {
		t.Fatal("cert public key does not match the private key")
	}
}
