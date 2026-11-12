package config

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
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
		Addr:   DefaultAddr,
		DBPath: DefaultDBPath,
		// Registration is invite-only by default: anyone who can reach the
		// server can otherwise create an account on it. The admin can enable
		// direct sign-up with `allow_registration: true`.
		AllowRegistration: false,
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

// configTemplate is the commented configuration file written by
// `passone config init`.
//
// Every setting is documented inline and the possible values are listed, so
// the file is usable without reading the source. The placeholders are
// replaced with the effective values, so the file always describes the
// configuration it was generated from.
const configTemplate = `# PassOne server configuration.
#
# The file is read at startup: changes take effect after a restart.
# Every value can also be set with an environment variable (see the end of
# this file), which takes precedence over the value written here.

# Address the server listens on.
#   "127.0.0.1:8321"  only this machine: use it with a reverse proxy
#   "0.0.0.0:8321"    every interface (the default: the mobile app has to
#                     reach the server over the network)
#   ":8321"           same as "0.0.0.0:8321"
addr: {{.Addr}}

# Path of the SQLite database. It can be absolute or relative to the working
# directory of the server. The directory is created if it does not exist.
db_path: {{.DBPath}}

# Allow the users to create an account directly from the app.
#   false  invite tokens only: the admin creates the user and hands over the
#          one-time token (recommended, the default)
#   true   anyone who can reach the server can register an account
allow_registration: {{.AllowRegistration}}

# Serve the admin web UI on /admin/. The admin token is still required to
# use it. Disable it if you only use the command line.
enable_ui: {{.EnableUI}}

# Secret used by the command line and by the admin web UI. If it is left
# empty a random one is generated and printed at startup. Keep it secret:
# it grants full control over the accounts.
admin_token: {{.AdminToken}}

# Certificate and private key used when tls_mode is "custom". Both must be
# set. The paths can be absolute or relative to the working directory.
tls_cert: {{.TLSCert}}
tls_key: {{.TLSKey}}

# How the server exposes the API over TLS.
#   "none"       plain HTTP (the default): a warning is logged at startup.
#                The data stays encrypted end-to-end, but the transport and
#                the metadata (user names, timestamps) are not.
#   "selfsigned" the server generates and keeps its own certificate
#                (tls-cert.pem / tls-key.pem) and serves HTTPS only: the
#                clients have to be paired with its SPKI fingerprint, which
#                the admin UI shows as a QR code.
#   "custom"     use tls_cert / tls_key, for example a certificate issued
#                by a CA or by Let's Encrypt.
tls_mode: {{.TLSMode}}

# How long a session token stays valid, as a Go duration (30m, 24h, 720h).
# Changing it does not revoke the sessions that were already issued.
session_ttl: {{.SessionTTL}}

# Upper bound on the memory a client may request when deriving its key
# (Argon2id). A higher value makes an offline brute-force of the master
# password more expensive, but slows down the login and the unlock. It is a
# safety net against a malicious client asking for an absurd amount of
# memory: the client cannot exceed it.
max_kdf_memory_mb: {{.MaxKDFMemoryMB}}

# Upper bound on the number of iterations a client may request for the key
# derivation. Same role as max_kdf_memory_mb.
max_kdf_iterations: {{.MaxKDFIterations}}

# Environment variables. They override the values written in this file:
#   PASSONE_ADDR         -> addr
#   PASSONE_DB_PATH      -> db_path
#   PASSONE_ADMIN_TOKEN  -> admin_token
#   PASSONE_TLS_CERT     -> tls_cert
#   PASSONE_TLS_KEY      -> tls_key
#   PASSONE_TLS_MODE     -> tls_mode
#   PASSONE_CONFIG       -> path of this file (command line only)
`

// Render returns the configuration as a commented YAML file.
//
// The result is parsed back before being returned: a configuration that
// cannot be read back would silently change the behaviour of the server.
func Render(cfg *Config) (string, error) {
	replacer := strings.NewReplacer(
		"{{.Addr}}", quote(cfg.Addr),
		"{{.DBPath}}", quote(cfg.DBPath),
		"{{.AllowRegistration}}", strconv.FormatBool(cfg.AllowRegistration),
		"{{.EnableUI}}", strconv.FormatBool(cfg.EnableUI),
		"{{.AdminToken}}", quote(cfg.AdminToken),
		"{{.TLSCert}}", quote(cfg.TLSCert),
		"{{.TLSKey}}", quote(cfg.TLSKey),
		"{{.TLSMode}}", quote(cfg.TLSMode),
		"{{.SessionTTL}}", cfg.SessionTTL.String(),
		"{{.MaxKDFMemoryMB}}", strconv.Itoa(cfg.MaxKDFMemoryMB),
		"{{.MaxKDFIterations}}", strconv.Itoa(cfg.MaxKDFIterations),
	)
	out := replacer.Replace(configTemplate)

	// The rendered file must describe the same configuration.
	var check Config
	if err := yaml.Unmarshal([]byte(out), &check); err != nil {
		return "", fmt.Errorf("generated configuration is not valid YAML: %w", err)
	}
	if check.Addr != cfg.Addr || check.DBPath != cfg.DBPath ||
		check.AllowRegistration != cfg.AllowRegistration ||
		check.EnableUI != cfg.EnableUI || check.AdminToken != cfg.AdminToken ||
		check.TLSCert != cfg.TLSCert || check.TLSKey != cfg.TLSKey ||
		check.TLSMode != cfg.TLSMode || check.SessionTTL != cfg.SessionTTL ||
		check.MaxKDFMemoryMB != cfg.MaxKDFMemoryMB ||
		check.MaxKDFIterations != cfg.MaxKDFIterations {
		return "", fmt.Errorf("generated configuration does not round-trip")
	}
	return out, nil
}

// quote renders a string as a double quoted YAML scalar.
func quote(s string) string {
	return strconv.Quote(s)
}

// Write saves the configuration in YAML format, with the comments that
// document every setting.
func Write(path string, cfg *Config) error {
	data, err := Render(cfg)
	if err != nil {
		return err
	}
	if dir := filepath.Dir(path); dir != "" && dir != "." {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
	}
	return os.WriteFile(path, []byte(data), 0o600)
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
