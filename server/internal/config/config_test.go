package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadNormalizesTLSMode(t *testing.T) {
	dir := t.TempDir()
	write := func(mode string) *Config {
		t.Helper()
		p := filepath.Join(dir, "config.yaml")
		content := "tls_mode: " + mode + "\n"
		if err := os.WriteFile(p, []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
		cfg, err := Load(p)
		if err != nil {
			t.Fatalf("Load(%q): %v", mode, err)
		}
		return cfg
	}

	for _, mode := range []string{"none", "custom", "selfsigned"} {
		if got := write(mode).TLSMode; got != mode {
			t.Errorf("tls_mode=%q → %q, want %q", mode, got, mode)
		}
	}
	for _, bad := range []string{"", "bogus", "TLS", "nonexistent"} {
		if got := write(bad).TLSMode; got != TLSModeNone {
			t.Errorf("tls_mode=%q → %q, want %q", bad, got, TLSModeNone)
		}
	}
}

func TestDefaultHasNoTLS(t *testing.T) {
	if got := Default().TLSMode; got != TLSModeNone {
		t.Errorf("Default().TLSMode = %q, want %q", got, TLSModeNone)
	}
}

func TestEnvOverrideTLSMode(t *testing.T) {
	cfg := Default()
	t.Setenv("PASSONE_TLS_MODE", "selfsigned")
	cfg.EnvOverride()
	if cfg.TLSMode != TLSModeSelfSigned {
		t.Errorf("TLSMode = %q, want %q", cfg.TLSMode, TLSModeSelfSigned)
	}
}
