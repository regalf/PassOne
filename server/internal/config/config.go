package config

import (
	"fmt"
	"os"
	"path/filepath"
	"time"

	"gopkg.in/yaml.v3"
)

// TLS mode values.
const (
	TLSModeNone       = "none"
	TLSModeCustom     = "custom"
	TLSModeSelfSigned = "selfsigned"
)

const (
	// DefaultAddr listens on all interfaces so clients on the network (e.g. the
	// mobile app) can reach the server out of the box. Set `addr` to a specific
	// host (or add a firewall rule) when the server must be reachable only from
	// this machine.
	DefaultAddr       = "0.0.0.0:8321"
	DefaultDBPath     = "passone.db"
	DefaultSessionTTL = 30 * 24 * time.Hour
)

// Config describes the PassOne server configuration.
type Config struct {
	// Addr is the address the server listens on (e.g. "0.0.0.0:8321").
	Addr string `yaml:"addr"`
	// DBPath is the path of the SQLite file.
	DBPath string `yaml:"db_path"`
	// AllowRegistration enables direct registration from the app.
	AllowRegistration bool `yaml:"allow_registration"`
	// EnableUI enables the admin web UI (embedded).
	EnableUI bool `yaml:"enable_ui"`
	// AdminToken is the secret used for admin calls (CLI/web UI).
	// If empty, a random one is generated and printed on first startup.
	AdminToken string `yaml:"admin_token"`
	// TLSCert/TLSKey enable direct TLS if both are set.
	TLSCert string `yaml:"tls_cert"`
	TLSKey  string `yaml:"tls_key"`
	// TLSMode selects how the server exposes the API over TLS:
	// "none"        — plain HTTP (default; a warning is logged at startup);
	// "custom"      — use TLSCert/TLSKey, which must both be set;
	// "selfsigned"  — the server generates/keeps its own certificate + key
	//                 (see internal/tlscert) and serves only TLS.
	TLSMode string `yaml:"tls_mode"`
	// SessionTTL is the duration of a session.
	SessionTTL time.Duration `yaml:"session_ttl"`
	// MaxKDFMemoryMB/KDFIterationsLimit are sanity limits on the KDF parameters.
	MaxKDFMemoryMB   int `yaml:"max_kdf_memory_mb"`
	MaxKDFIterations int `yaml:"max_kdf_iterations"`
}

// Default returns a configuration with default values.
func Default() *Config {
	return &Config{
		Addr:              DefaultAddr,
		DBPath:            DefaultDBPath,
		AllowRegistration: true,
		EnableUI:          true,
		TLSMode:           "none",
		SessionTTL:        DefaultSessionTTL,
		MaxKDFMemoryMB:    2048,
		MaxKDFIterations:  10000000,
	}
}

// Load reads the configuration from a YAML file, applying defaults for missing fields.
func Load(path string) (*Config, error) {
	cfg := Default()
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("reading config: %w", err)
	}
	if err := yaml.Unmarshal(data, cfg); err != nil {
		return nil, fmt.Errorf("parse config: %w", err)
	}
	if cfg.Addr == "" {
		cfg.Addr = DefaultAddr
	}
	if cfg.DBPath == "" {
		cfg.DBPath = DefaultDBPath
	}
	if cfg.SessionTTL == 0 {
		cfg.SessionTTL = DefaultSessionTTL
	}
	if cfg.MaxKDFMemoryMB <= 0 {
		cfg.MaxKDFMemoryMB = 2048
	}
	if cfg.MaxKDFIterations <= 0 {
		cfg.MaxKDFIterations = 10000000
	}
	switch cfg.TLSMode {
	case "", "none", "custom", "selfsigned":
		if cfg.TLSMode == "" {
			cfg.TLSMode = "none"
		}
	default:
		cfg.TLSMode = "none"
	}
	// AdminToken: if empty it stays empty; the server will generate a random default.
	return cfg, nil
}

// Write saves the configuration in YAML format.
func Write(path string, cfg *Config) error {
	if dir := filepath.Dir(path); dir != "" && dir != "." {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
	}
	data, err := yaml.Marshal(cfg)
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o600)
}

// EnvOverride applies environment variables as overrides (PASSONE_ prefix).
func (c *Config) EnvOverride() {
	if v := os.Getenv("PASSONE_ADDR"); v != "" {
		c.Addr = v
	}
	if v := os.Getenv("PASSONE_DB_PATH"); v != "" {
		c.DBPath = v
	}
	if v := os.Getenv("PASSONE_ADMIN_TOKEN"); v != "" {
		c.AdminToken = v
	}
	if v := os.Getenv("PASSONE_TLS_CERT"); v != "" {
		c.TLSCert = v
	}
	if v := os.Getenv("PASSONE_TLS_KEY"); v != "" {
		c.TLSKey = v
	}
	if v := os.Getenv("PASSONE_TLS_MODE"); v != "" {
		c.TLSMode = v
	}
}
