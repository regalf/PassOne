package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"passone/internal/api"
	"passone/internal/config"
	"passone/internal/crypto"
	"passone/internal/store"
	"passone/internal/tlscert"
	"passone/internal/webui"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}
	cmd, args := os.Args[1], os.Args[2:]
	log := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelInfo}))

	var err error
	switch cmd {
	case "serve":
		err = cmdServe(log, args)
	case "tls":
		err = cmdTLS(log, args)
	case "user":
		err = cmdUser(log, args)
	case "config":
		err = cmdConfig(args)
	case "backup":
		err = cmdBackup(log, args)
	case "help", "--help", "-h":
		usage()
	default:
		fmt.Fprintf(os.Stderr, "unknown command: %s\n\n", cmd)
		usage()
		os.Exit(1)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

const (
	defaultTLSCert = "tls-cert.pem"
	defaultTLSKey  = "tls-key.pem"
)

func usage() {
	fmt.Print(`PassOne - password manager self-hosted

Uso:
  passone serve [--config config.yaml] [--no-ui] [--addr :8321]
  passone tls gen [--force]
  passone tls fingerprint
  passone tls rotate
  passone user create <username>
  passone user list
  passone user disable <username>
  passone user reset-invite <username>
  passone config init [--out config.yaml]
  passone backup --out backup.json
  passone help
`)
}

// ---------------- serve ----------------

func cmdServe(log *slog.Logger, args []string) error {
	fs := flag.NewFlagSet("serve", flag.ContinueOnError)
	configPath := fs.String("config", "config.yaml", "path to the configuration file")
	noUI := fs.Bool("no-ui", false, "disable the admin web UI")
	addr := fs.String("addr", "", "override the listen address")
	_ = fs.Parse(args)

	cfg, err := config.Load(*configPath)
	if err != nil {
		return err
	}
	cfg.EnvOverride()
	if *noUI {
		cfg.EnableUI = false
	}
	if *addr != "" {
		cfg.Addr = *addr
	}

	st, err := store.Open(cfg.DBPath)
	if err != nil {
		return err
	}
	defer st.Close()

	if cfg.TLSMode == config.TLSModeSelfSigned {
		info, err := tlscert.Ensure(certPath(cfg), keyPath(cfg), time.Now())
		if err != nil {
			return err
		}
		logConfigTLS(log, cfg, info)
	} else if cfg.TLSMode == config.TLSModeCustom && (cfg.TLSCert == "" || cfg.TLSKey == "") {
		return errors.New("tls_mode \"custom\" requires both tls_cert and tls_key")
	}

	srv := api.New(cfg, st, log)
	handler := srv.Routes()
	if cfg.EnableUI {
		handler = webui.WithAdminUI(handler, srv.AdminToken())
	}

	usingTLS := false
	switch cfg.TLSMode {
	case config.TLSModeSelfSigned:
		usingTLS = true
	case config.TLSModeCustom:
		usingTLS = true
	case config.TLSModeNone:
		usingTLS = cfg.TLSCert != "" && cfg.TLSKey != ""
		if !usingTLS {
			log.Warn("server running WITHOUT TLS/HTTPS — the transport is not encrypted; end-to-end encryption stays active, but consider tls_mode \"selfsigned\" or an HTTPS reverse proxy (e.g. Caddy).")
		}
	}
	if usingTLS && cfg.TLSMode != config.TLSModeSelfSigned {
		log.Info("TLS enabled", "cert", cfg.TLSCert, "mode", cfg.TLSMode)
	}
	if cfg.AdminToken == "" {
		// Log only a prefix: the full token is a secret and must not end up
		// in log files. The admin can still read it from the CLI output.
		tok := srv.AdminToken()
		prefix := tok
		if len(tok) > 12 {
			prefix = tok[:12] + "…"
		}
		log.Info("admin token generated (save it!)", "admin_token", prefix, "db_path", cfg.DBPath)
	} else {
		log.Info("admin token from configuration", "db_path", cfg.DBPath)
	}

	httpServer := &http.Server{
		Addr:              cfg.Addr,
		Handler:           handler,
		ReadHeaderTimeout: 10 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() {
		log.Info("PassOne server listening", "addr", cfg.Addr, "ui", cfg.EnableUI, "tls", usingTLS)
		if usingTLS {
			errCh <- httpServer.ListenAndServeTLS(certPath(cfg), keyPath(cfg))
		} else {
			errCh <- httpServer.ListenAndServe()
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)

	select {
	case err := <-errCh:
		return err
	case sig := <-stop:
		log.Info("shutting down", "signal", sig.String())
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		return httpServer.Shutdown(ctx)
	}
}

// ---------------- tls ----------------

func cmdTLS(log *slog.Logger, args []string) error {
	if len(args) < 1 {
		return errors.New("usage: passone tls gen|fingerprint|rotate")
	}
	sub := args[0]

	cfg, err := loadConfigForCLI()
	if err != nil {
		return err
	}
	if cfg.TLSMode != config.TLSModeSelfSigned {
		return fmt.Errorf("tls_mode is %q, not %q: the tls commands operate on the self-signed certificate", cfg.TLSMode, config.TLSModeSelfSigned)
	}
	cert, key := certPath(cfg), keyPath(cfg)
	now := time.Now()

	switch sub {
	case "gen":
		force := false
		fs := flag.NewFlagSet("tls gen", flag.ContinueOnError)
		fs.BoolVar(&force, "force", false, "regenerate the key + certificate")
		_ = fs.Parse(args[1:])
		var info *tlscert.Info
		if force {
			info, err = tlscert.Rotate(cert, key, now)
		} else {
			info, err = tlscert.Ensure(cert, key, now)
		}
		if err != nil {
			return err
		}
		printTLSInfo(info, cert, key, log)
	case "fingerprint":
		info, err := tlscert.Inform(cert)
		if err != nil {
			return err
		}
		printTLSInfo(info, cert, key, log)
	case "rotate":
		info, err := tlscert.Rotate(cert, key, now)
		if err != nil {
			return err
		}
		fmt.Printf("key rotated: the SPKI fingerprint changed, re-pair every client device.\n")
		printTLSInfo(info, cert, key, log)
	default:
		return fmt.Errorf("unknown subcommand: %s", sub)
	}
	return nil
}

func printTLSInfo(info *tlscert.Info, cert, key string, log *slog.Logger) {
	fmt.Printf("certificate      %s\nprivate key      %s\n", cert, key)
	fmt.Printf("fingerprint (SPKI SHA-256)\n  %s\n", info.Fingerprint)
	fmt.Printf("public key       %s\nvalid from       %s\nvalid until      %s\n",
		info.PublicKey, info.NotBefore.Format(time.RFC3339), info.NotAfter.Format(time.RFC3339))
}

func certPath(cfg *config.Config) string {
	if cfg.TLSCert != "" {
		return cfg.TLSCert
	}
	return defaultTLSCert
}

func keyPath(cfg *config.Config) string {
	if cfg.TLSKey != "" {
		return cfg.TLSKey
	}
	return defaultTLSKey
}

func logConfigTLS(log *slog.Logger, cfg *config.Config, info *tlscert.Info) {
	log.Info("self-signed TLS certificate ready",
		"cert", certPath(cfg),
		"key", keyPath(cfg),
		"fingerprint_spki", info.Fingerprint,
		"valid_until", info.NotAfter.Format(time.RFC3339))
	log.Warn("backup the certificate and private key (like the recovery key): losing the private key forces re-pairing of every client device")
}

// ---------------- user ----------------

func cmdUser(log *slog.Logger, args []string) error {
	if len(args) < 1 {
		return errors.New("usage: passone user create|list|disable|reset-invite")
	}
	sub, rest := args[0], args[1:]

	cfg, err := loadConfigForCLI()
	if err != nil {
		return err
	}
	st, err := store.Open(cfg.DBPath)
	if err != nil {
		return err
	}
	defer st.Close()

	switch sub {
	case "create":
		if len(rest) != 1 {
			return errors.New("usage: passone user create <username>")
		}
		token, err := st.CreatePendingUser(rest[0])
		if err != nil {
			return err
		}
		fmt.Printf("user '%s' created (pending)\ninvite token: %s\n", rest[0], token)
		return nil
	case "list":
		users, err := st.ListUsers()
		if err != nil {
			return err
		}
		for _, u := range users {
			fmt.Printf("%d\t%s\t%s\trev=%d\n", u.ID, u.Username, u.Status, u.Revision)
		}
		return nil
	case "disable":
		if len(rest) != 1 {
			return errors.New("usage: passone user disable <username>")
		}
		return disableUser(st, rest[0])
	case "reset-invite":
		if len(rest) != 1 {
			return errors.New("usage: passone user reset-invite <username>")
		}
		token, err := st.ResetInviteToken(rest[0])
		if err != nil {
			return err
		}
		fmt.Printf("new invite token: %s\n", token)
		return nil
	default:
		return fmt.Errorf("unknown subcommand: %s", sub)
	}
}

func disableUser(st *store.Store, username string) error {
	u, err := st.GetUserByUsername(username)
	if err != nil {
		return err
	}
	// Direct state update via UpdateAuthMaterial is not enough:
	// we use a plain UPDATE.
	return st.SetUserStatus(u.ID, store.StatusDisabled)
}

func loadConfigForCLI() (*config.Config, error) {
	path := "config.yaml"
	if v := os.Getenv("PASSONE_CONFIG"); v != "" {
		path = v
	}
	cfg, err := config.Load(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, errors.New("config.yaml not found: run 'passone config init'")
		}
		return nil, err
	}
	cfg.EnvOverride()
	return cfg, nil
}

// ---------------- config init ----------------

func cmdConfig(args []string) error {
	if len(args) < 1 || args[0] != "init" {
		return errors.New("usage: passone config init [--out config.yaml]")
	}
	fs := flag.NewFlagSet("config", flag.ContinueOnError)
	out := fs.String("out", "config.yaml", "output file")
	_ = fs.Parse(args[1:])
	cfg := config.Default()
	// Generates a random admin token so it doesn't need to be printed.
	token, err := crypto.RandomHex(32)
	if err != nil {
		return err
	}
	cfg.AdminToken = "admin_" + token
	if err := config.Write(*out, cfg); err != nil {
		return err
	}
	fmt.Printf("configuration written to %s\n", *out)
	return nil
}

// ---------------- backup ----------------

func cmdBackup(log *slog.Logger, args []string) error {
	fs := flag.NewFlagSet("backup", flag.ContinueOnError)
	out := fs.String("out", "passone-backup.json", "output file")
	_ = fs.Parse(args)

	cfg, err := loadConfigForCLI()
	if err != nil {
		return err
	}
	st, err := store.Open(cfg.DBPath)
	if err != nil {
		return err
	}
	defer st.Close()

	users, err := st.ListUsers()
	if err != nil {
		return err
	}
	type backupUser struct {
		Username              string `json:"username"`
		Status                string `json:"status"`
		SaltB64               string `json:"salt_b64,omitempty"`
		KDFAlgorithm          string `json:"kdf_algorithm"`
		KDFParams             any    `json:"kdf_params"`
		AuthHashB64           string `json:"auth_hash_b64,omitempty"`
		RecoveryHashB64       string `json:"recovery_hash_b64,omitempty"`
		VaultKeyWrappedB64    string `json:"vault_key_wrapped_b64,omitempty"`
		VaultKeyWrappedRecB64 string `json:"vault_key_wrapped_recov_b64,omitempty"`
		VaultBlobB64          string `json:"vault_blob_b64,omitempty"`
		VaultNonceB64         string `json:"vault_nonce_b64,omitempty"`
		VaultRevision         int64  `json:"vault_revision"`
		UpdatedAt             string `json:"updated_at"`
	}
	var usersBackup []backupUser
	for _, su := range users {
		u, err := st.GetUserByID(su.ID)
		if err != nil {
			return err
		}
		bu := backupUser{
			Username:      u.Username,
			Status:        u.Status,
			KDFAlgorithm:  u.KDFAlgorithm,
			KDFParams:     u.KDFParams,
			VaultRevision: u.VaultRevision,
			UpdatedAt:     u.UpdatedAt.Format(time.RFC3339),
		}
		if u.Salt != nil {
			bu.SaltB64 = crypto.EncodeBase64(u.Salt)
		}
		if u.AuthHash != nil {
			bu.AuthHashB64 = crypto.EncodeBase64(u.AuthHash)
		}
		if u.RecoveryHash != nil {
			bu.RecoveryHashB64 = crypto.EncodeBase64(u.RecoveryHash)
		}
		if u.VaultKeyWrapped != nil {
			bu.VaultKeyWrappedB64 = crypto.EncodeBase64(u.VaultKeyWrapped)
		}
		if u.VaultKeyWrappedRecov != nil {
			bu.VaultKeyWrappedRecB64 = crypto.EncodeBase64(u.VaultKeyWrappedRecov)
		}
		if u.VaultBlob != nil {
			bu.VaultBlobB64 = crypto.EncodeBase64(u.VaultBlob)
		}
		if u.VaultNonce != nil {
			bu.VaultNonceB64 = crypto.EncodeBase64(u.VaultNonce)
		}
		usersBackup = append(usersBackup, bu)
	}

	type tlsBackup struct {
		Mode       string `json:"mode,omitempty"`
		CertPEMB64 string `json:"cert_pem_b64,omitempty"`
		KeyPEMB64  string `json:"key_pem_b64,omitempty"`
	}
	var tlsBk *tlsBackup
	if cfg.TLSMode == config.TLSModeSelfSigned {
		if certB64, err := fileToB64(certPath(cfg)); err == nil {
			keyB64, keyErr := fileToB64(keyPath(cfg))
			if keyErr == nil {
				tlsBk = &tlsBackup{Mode: cfg.TLSMode, CertPEMB64: certB64, KeyPEMB64: keyB64}
			}
		}
	}

	type backupFile struct {
		Format    string       `json:"format"`
		Version   int          `json:"version"`
		CreatedAt string       `json:"created_at"`
		TLS       *tlsBackup   `json:"tls,omitempty"`
		Users     []backupUser `json:"users"`
	}
	outData := backupFile{
		Format:    "passone-backup",
		Version:   2,
		CreatedAt: time.Now().UTC().Format(time.RFC3339),
		TLS:       tlsBk,
		Users:     usersBackup,
	}
	data, err := json.MarshalIndent(outData, "", "  ")
	if err != nil {
		return err
	}
	if err := os.WriteFile(*out, data, 0o600); err != nil {
		return err
	}
	log.Info("backup completed", "file", *out, "users", len(usersBackup), "tls", tlsBk != nil)
	return nil
}

func fileToB64(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return crypto.EncodeBase64(b), nil
}
