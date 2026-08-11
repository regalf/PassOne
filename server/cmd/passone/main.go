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
	case "user":
		err = cmdUser(log, args)
	case "config":
		err = cmdConfig(args)
	case "backup":
		err = cmdBackup(log, args)
	case "help", "--help", "-h":
		usage()
	default:
		fmt.Fprintf(os.Stderr, "comando sconosciuto: %s\n\n", cmd)
		usage()
		os.Exit(1)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "errore:", err)
		os.Exit(1)
	}
}

func usage() {
	fmt.Print(`PassOne - password manager self-hosted

Uso:
  passone serve [--config config.yaml] [--no-ui] [--addr :8321]
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
	configPath := fs.String("config", "config.yaml", "percorso file di configurazione")
	noUI := fs.Bool("no-ui", false, "disabilita la web UI admin")
	addr := fs.String("addr", "", "override indirizzo di ascolto")
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

	srv := api.New(cfg, st, log)
	handler := srv.Routes()
	if cfg.EnableUI {
		handler = webui.WithAdminUI(handler, srv.AdminToken())
	}

	if cfg.TLSCert == "" || cfg.TLSKey == "" {
		log.Warn("server in esecuzione SENZA TLS/HTTPS — il trasporto non è cifrato; la crittografia end-to-end resta attiva ma si consiglia di usare un reverse proxy HTTPS (es. Caddy).")
	} else {
		log.Info("TLS abilitato", "cert", cfg.TLSCert)
	}
	if cfg.AdminToken == "" {
		log.Info("admin token generato (salvalo!)", "admin_token", srv.AdminToken(), "db_path", cfg.DBPath)
	} else {
		log.Info("admin token da configurazione", "db_path", cfg.DBPath)
	}

	httpServer := &http.Server{
		Addr:              cfg.Addr,
		Handler:           handler,
		ReadHeaderTimeout: 10 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() {
		log.Info("PassOne server in ascolto", "addr", cfg.Addr, "ui", cfg.EnableUI)
		if cfg.TLSCert != "" && cfg.TLSKey != "" {
			errCh <- httpServer.ListenAndServeTLS(cfg.TLSCert, cfg.TLSKey)
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
		log.Info("arresto in corso", "signal", sig.String())
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		return httpServer.Shutdown(ctx)
	}
}

// ---------------- user ----------------

func cmdUser(log *slog.Logger, args []string) error {
	if len(args) < 1 {
		return errors.New("uso: passone user create|list|disable|reset-invite")
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
			return errors.New("uso: passone user create <username>")
		}
		token, err := st.CreatePendingUser(rest[0])
		if err != nil {
			return err
		}
		fmt.Printf("utente '%s' creato (pending)\ninvite token: %s\n", rest[0], token)
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
			return errors.New("uso: passone user disable <username>")
		}
		return disableUser(st, rest[0])
	case "reset-invite":
		if len(rest) != 1 {
			return errors.New("uso: passone user reset-invite <username>")
		}
		token, err := st.ResetInviteToken(rest[0])
		if err != nil {
			return err
		}
		fmt.Printf("nuovo invite token: %s\n", token)
		return nil
	default:
		return fmt.Errorf("sottocomando sconosciuto: %s", sub)
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
			return nil, errors.New("config.yaml non trovata: avvia 'passone config init'")
		}
		return nil, err
	}
	cfg.EnvOverride()
	return cfg, nil
}

// ---------------- config init ----------------

func cmdConfig(args []string) error {
	if len(args) < 1 || args[0] != "init" {
		return errors.New("uso: passone config init [--out config.yaml]")
	}
	fs := flag.NewFlagSet("config", flag.ContinueOnError)
	out := fs.String("out", "config.yaml", "file di output")
	_ = fs.Parse(args[1:])
	cfg := config.Default()
	// Generates a random admin token so it doesn't need to be printed.
	token, err := crypto.RandomHex(24)
	if err != nil {
		return err
	}
	cfg.AdminToken = "admin_" + token
	if err := config.Write(*out, cfg); err != nil {
		return err
	}
	fmt.Printf("configurazione scritta in %s\n", *out)
	return nil
}

// ---------------- backup ----------------

func cmdBackup(log *slog.Logger, args []string) error {
	fs := flag.NewFlagSet("backup", flag.ContinueOnError)
	out := fs.String("out", "passone-backup.json", "file di output")
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
		Username             string    `json:"username"`
		Status               string    `json:"status"`
		SaltB64              string    `json:"salt_b64,omitempty"`
		KDFAlgorithm         string    `json:"kdf_algorithm"`
		KDFParams            any       `json:"kdf_params"`
		AuthHashB64          string    `json:"auth_hash_b64,omitempty"`
		RecoveryHashB64      string    `json:"recovery_hash_b64,omitempty"`
		VaultKeyWrappedB64   string    `json:"vault_key_wrapped_b64,omitempty"`
		VaultKeyWrappedRecB64 string   `json:"vault_key_wrapped_recov_b64,omitempty"`
		VaultBlobB64         string    `json:"vault_blob_b64,omitempty"`
		VaultNonceB64        string    `json:"vault_nonce_b64,omitempty"`
		VaultRevision        int64     `json:"vault_revision"`
		UpdatedAt            string    `json:"updated_at"`
	}
	var outData []backupUser
	for _, su := range users {
		u, err := st.GetUserByID(su.ID)
		if err != nil {
			return err
		}
		bu := backupUser{
			Username:             u.Username,
			Status:               u.Status,
			KDFAlgorithm:         u.KDFAlgorithm,
			KDFParams:            u.KDFParams,
			VaultRevision:        u.VaultRevision,
			UpdatedAt:            u.UpdatedAt.Format(time.RFC3339),
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
		outData = append(outData, bu)
	}
	data, err := json.MarshalIndent(outData, "", "  ")
	if err != nil {
		return err
	}
	if err := os.WriteFile(*out, data, 0o600); err != nil {
		return err
	}
	log.Info("backup completato", "file", *out, "utenti", len(outData))
	return nil
}
