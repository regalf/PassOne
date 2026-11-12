package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"gopkg.in/yaml.v3"
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

// The generated file must be readable back and describe the same
// configuration: a file that cannot be loaded would change the behaviour of
// the server without any notice.
func TestRenderRoundTrip(t *testing.T) {
	cfg := Default()
	cfg.AdminToken = "admin_deadbeef"
	cfg.TLSMode = TLSModeSelfSigned
	cfg.SessionTTL = 48 * time.Hour

	out, err := Render(cfg)
	if err != nil {
		t.Fatal(err)
	}

	var loaded Config
	if err := yaml.Unmarshal([]byte(out), &loaded); err != nil {
		t.Fatalf("the rendered file is not valid YAML: %v", err)
	}
	if loaded.Addr != cfg.Addr || loaded.DBPath != cfg.DBPath ||
		loaded.AllowRegistration != cfg.AllowRegistration ||
		loaded.EnableUI != cfg.EnableUI || loaded.AdminToken != cfg.AdminToken ||
		loaded.TLSCert != cfg.TLSCert || loaded.TLSKey != cfg.TLSKey ||
		loaded.TLSMode != cfg.TLSMode || loaded.SessionTTL != cfg.SessionTTL ||
		loaded.MaxKDFMemoryMB != cfg.MaxKDFMemoryMB ||
		loaded.MaxKDFIterations != cfg.MaxKDFIterations {
		t.Errorf("the rendered file does not round-trip:\ngot  %+v\nwant %+v", loaded, *cfg)
	}
}

// Every setting of the configuration file must be documented in the file
// itself, with the possible values.
func TestRenderDocumentsEverySetting(t *testing.T) {
	out, err := Render(Default())
	if err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{
		"addr:", "db_path:", "allow_registration:", "enable_ui:",
		"admin_token:", "tls_cert:", "tls_key:", "tls_mode:",
		"session_ttl:", "max_kdf_memory_mb:", "max_kdf_iterations:",
	} {
		if !strings.Contains(out, key) {
			t.Errorf("the generated file does not document %q", key)
		}
	}
	// The possible values of tls_mode are listed.
	for _, mode := range []string{"none", "selfsigned", "custom"} {
		if !strings.Contains(out, `"`+mode+`"`) {
			t.Errorf("the generated file does not document the tls_mode value %q", mode)
		}
	}
	// The environment variables that override the file are documented.
	for _, env := range []string{
		"PASSONE_ADDR", "PASSONE_DB_PATH", "PASSONE_ADMIN_TOKEN",
		"PASSONE_TLS_CERT", "PASSONE_TLS_KEY", "PASSONE_TLS_MODE",
	} {
		if !strings.Contains(out, env) {
			t.Errorf("the generated file does not document %q", env)
		}
	}
}

// The file written by `config init` must be loadable by the server.
func TestWriteThenLoad(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.yaml")
	cfg := Default()
	cfg.AdminToken = "admin_test"
	if err := Write(path, cfg); err != nil {
		t.Fatal(err)
	}
	loaded, err := Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if loaded.Addr != cfg.Addr || loaded.AdminToken != cfg.AdminToken ||
		loaded.SessionTTL != cfg.SessionTTL ||
		loaded.AllowRegistration != cfg.AllowRegistration {
		t.Errorf("the written file does not load back: %+v", loaded)
	}
	// The file holds a secret: it must not be world readable.
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if perm := info.Mode().Perm(); perm != 0o600 {
		t.Errorf("the configuration file has mode %o, want 600", perm)
	}
}
