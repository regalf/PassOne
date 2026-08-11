package config

import (
	"fmt"
	"os"
	"path/filepath"
	"time"

	"gopkg.in/yaml.v3"
)

const (
	DefaultAddr      = "127.0.0.1:8321"
	DefaultDBPath    = "passone.db"
	DefaultSessionTTL = 30 * 24 * time.Hour
)

// Config descrive la configurazione del server PassOne.
type Config struct {
	// Addr è l'indirizzo su cui il server ascolta (es. "127.0.0.1:8321").
	Addr string `yaml:"addr"`
	// DBPath è il percorso del file SQLite.
	DBPath string `yaml:"db_path"`
	// AllowRegistration abilita la registrazione diretta dall'app.
	AllowRegistration bool `yaml:"allow_registration"`
	// EnableUI abilita la web UI admin (embedded).
	EnableUI bool `yaml:"enable_ui"`
	// AdminToken è il segreto usato per le chiamate admin (CLI/web UI).
	// Se vuoto, ne viene generato uno casuale e stampato al primo avvio.
	AdminToken string `yaml:"admin_token"`
	// TLSCert/TLSKey abilitano TLS diretto se entrambi presenti.
	TLSCert string `yaml:"tls_cert"`
	TLSKey  string `yaml:"tls_key"`
	// SessionTTL è la durata di una sessione.
	SessionTTL time.Duration `yaml:"session_ttl"`
	// MaxKDFMemoryMB/KDFIterationsLimit sono limiti di sanità sui parametri KDF.
	MaxKDFMemoryMB    int `yaml:"max_kdf_memory_mb"`
	MaxKDFIterations  int `yaml:"max_kdf_iterations"`
}

// Default restituisce una configurazione con valori di default.
func Default() *Config {
	return &Config{
		Addr:               DefaultAddr,
		DBPath:             DefaultDBPath,
		AllowRegistration:  true,
		EnableUI:           true,
		SessionTTL:         DefaultSessionTTL,
		MaxKDFMemoryMB:     2048,
		MaxKDFIterations:   10000000,
	}
}

// Load legge la configurazione da file YAML, applicando i default per i campi mancanti.
func Load(path string) (*Config, error) {
	cfg := Default()
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("lettura config: %w", err)
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
	// AdminToken: se vuoto resta vuoto; il server genererà un default random.
	return cfg, nil
}

// Write salva la configurazione in formato YAML.
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

// EnvOverride applica le variabili d'ambiente come override (prefisso PASSONE_).
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
}
