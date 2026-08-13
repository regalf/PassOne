package store

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"passone/internal/crypto"

	_ "modernc.org/sqlite"
)

const schema = `
CREATE TABLE IF NOT EXISTS users (
	id                      INTEGER PRIMARY KEY AUTOINCREMENT,
	username                TEXT NOT NULL UNIQUE,
	status                  TEXT NOT NULL DEFAULT 'pending',
	invite_token_hash       BLOB,
	salt                    BLOB,
	kdf_algorithm           TEXT NOT NULL DEFAULT 'argon2id',
	kdf_params              TEXT NOT NULL DEFAULT '{}',
	auth_hash               BLOB,
	recovery_hash           BLOB,
	vault_key_wrapped       BLOB,
	vault_key_wrapped_recov BLOB,
	vault_blob              BLOB,
	vault_nonce             BLOB,
	vault_revision          INTEGER NOT NULL DEFAULT 0,
	created_at              TEXT NOT NULL,
	updated_at              TEXT NOT NULL,
	last_login_at           TEXT
);

CREATE TABLE IF NOT EXISTS sessions (
	id         INTEGER PRIMARY KEY AUTOINCREMENT,
	user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
	token_hash BLOB NOT NULL UNIQUE,
	device_name TEXT,
	created_at TEXT NOT NULL,
	expires_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_sessions_token ON sessions(token_hash);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);
`

const (
	StatusPending = "pending"
	StatusActive  = "active"
	StatusDisabled = "disabled"
)

// KDFParams are the KDF parameters. m is in KiB (Argon2 convention).
type KDFParams struct {
	MemoryKiB   uint32 `json:"m"`
	Iterations  uint32 `json:"t"`
	Parallelism uint8  `json:"p"`
}

type User struct {
	ID                   int64
	Username             string
	Status               string
	InviteTokenHash      []byte
	Salt                 []byte
	KDFAlgorithm         string
	KDFParams            KDFParams
	AuthHash             []byte
	RecoveryHash         []byte
	VaultKeyWrapped      []byte
	VaultKeyWrappedRecov []byte
	VaultBlob            []byte
	VaultNonce           []byte
	VaultRevision        int64
	CreatedAt            time.Time
	UpdatedAt            time.Time
	LastLoginAt          time.Time

	kdfParamsRaw  string
	createdAtRaw  string
	updatedAtRaw  string
	lastLoginRaw  sql.NullString
}

type Session struct {
	ID         int64
	UserID     int64
	TokenHash  []byte
	DeviceName string
	CreatedAt  time.Time
	ExpiresAt  time.Time
}

// Store is the SQLite database.
type Store struct {
	db *sql.DB
}

// Open opens (creating it if needed) the SQLite database at path dbPath.
func Open(dbPath string) (*Store, error) {
	if dir := filepath.Dir(dbPath); dir != "" && dir != "." {
		if err := os.MkdirAll(dir, 0o700); err != nil {
			return nil, fmt.Errorf("creating db directory: %w", err)
		}
	}
	dsn := "file:" + dbPath + "?_pragma=journal_mode(WAL)&_pragma=busy_timeout(5000)&_pragma=foreign_keys(ON)"
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("opening sqlite: %w", err)
	}
	// WAL multi-writer is not needed: single process, but useful for the concurrent CLI.
	db.SetMaxOpenConns(1)
	if _, err := db.Exec(schema); err != nil {
		db.Close()
		return nil, fmt.Errorf("schema migration: %w", err)
	}
	return &Store{db: db}, nil
}

// Close closes the database.
func (s *Store) Close() error { return s.db.Close() }

// Ping verifies that the database is reachable.
func (s *Store) Ping() error { return s.db.Ping() }

// CreatePendingUser creates a user in pending status and returns the invite token.
func (s *Store) CreatePendingUser(username string) (string, error) {
	token, err := crypto.RandomHex(32)
	if err != nil {
		return "", err
	}
	if _, err := s.db.Exec(
		`INSERT INTO users (username, status, invite_token_hash, kdf_params, created_at, updated_at)
		 VALUES (?, ?, ?, '{}', ?, ?)`,
		strings.TrimSpace(username), StatusPending, hashToken([]byte(token)), now(), now(),
	); err != nil {
		return "", fmt.Errorf("create user: %w", err)
	}
	return token, nil
}

// InsertUser inserts a user already complete with auth materials (direct registration).
func (s *Store) InsertUser(u *User) (int64, error) {
	kp, err := json.Marshal(u.KDFParams)
	if err != nil {
		return 0, err
	}
	res, err := s.db.Exec(
		`INSERT INTO users (username, status, salt, kdf_algorithm, kdf_params, auth_hash,
		        recovery_hash, vault_key_wrapped, vault_key_wrapped_recov, vault_blob, vault_nonce,
		        vault_revision, created_at, updated_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		u.Username, StatusActive, u.Salt, u.KDFAlgorithm, string(kp), u.AuthHash, u.RecoveryHash,
		u.VaultKeyWrapped, u.VaultKeyWrappedRecov, u.VaultBlob, u.VaultNonce, u.VaultRevision,
		now(), now(),
	)
	if err != nil {
		return 0, fmt.Errorf("insert user: %w", err)
	}
	return res.LastInsertId()
}

// ResetInviteToken generates a new invite token for the user (if pending).
func (s *Store) ResetInviteToken(username string) (string, error) {
	token, err := crypto.RandomHex(32)
	if err != nil {
		return "", err
	}
	res, err := s.db.Exec(
		`UPDATE users SET invite_token_hash = ?, updated_at = ? WHERE username = ? AND status = ?`,
		hashToken([]byte(token)), now(), strings.TrimSpace(username), StatusPending,
	)
	if err != nil {
		return "", err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return "", ErrNotFound
	}
	return token, nil
}

// GetUserByUsername retrieves a user by username.
func (s *Store) GetUserByUsername(username string) (*User, error) {
	return s.scanUser(s.db.QueryRow(
		`SELECT id, username, status, invite_token_hash, salt, kdf_algorithm, kdf_params,
		        auth_hash, recovery_hash, vault_key_wrapped, vault_key_wrapped_recov,
		        vault_blob, vault_nonce, vault_revision, created_at, updated_at, last_login_at
		 FROM users WHERE username = ?`, strings.TrimSpace(username)))
}

// GetUserByID retrieves a user by ID.
func (s *Store) GetUserByID(id int64) (*User, error) {
	return s.scanUser(s.db.QueryRow(
		`SELECT id, username, status, invite_token_hash, salt, kdf_algorithm, kdf_params,
		        auth_hash, recovery_hash, vault_key_wrapped, vault_key_wrapped_recov,
		        vault_blob, vault_nonce, vault_revision, created_at, updated_at, last_login_at
		 FROM users WHERE id = ?`, id))
}

// ListUsers lists all users (username, status, revision, dates).
type UserSummary struct {
	ID       int64
	Username string
	Status   string
	Revision int64
	Created  time.Time
	Updated  time.Time
}

func (s *Store) ListUsers() ([]UserSummary, error) {
	rows, err := s.db.Query(
		`SELECT id, username, status, vault_revision, created_at, updated_at FROM users ORDER BY username`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []UserSummary
	for rows.Next() {
		var u UserSummary
		var c, up string
		if err := rows.Scan(&u.ID, &u.Username, &u.Status, &u.Revision, &c, &up); err != nil {
			return nil, err
		}
		var err error
		if u.Created, err = parseTime(c); err != nil {
			return nil, err
		}
		if u.Updated, err = parseTime(up); err != nil {
			return nil, err
		}
		out = append(out, u)
	}
	return out, rows.Err()
}

// DeleteUser permanently deletes a user and their sessions.
func (s *Store) DeleteUser(id int64) error {
	res, err := s.db.Exec(`DELETE FROM users WHERE id = ?`, id)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return ErrNotFound
	}
	return nil
}

// ActivateUser activates a pending user with the auth materials.
func (s *Store) ActivateUser(u *User, kdf KDFParams) error {
	kp, err := json.Marshal(kdf)
	if err != nil {
		return err
	}
	res, err := s.db.Exec(
		`UPDATE users SET status = ?, salt = ?, kdf_algorithm = ?, kdf_params = ?,
		        auth_hash = ?, recovery_hash = ?, vault_key_wrapped = ?, vault_key_wrapped_recov = ?,
		        vault_blob = ?, vault_nonce = ?, vault_revision = ?, invite_token_hash = NULL, updated_at = ?
		 WHERE id = ? AND status = ?`,
		StatusActive, u.Salt, u.KDFAlgorithm, string(kp), u.AuthHash, u.RecoveryHash,
		u.VaultKeyWrapped, u.VaultKeyWrappedRecov, u.VaultBlob, u.VaultNonce, u.VaultRevision,
		now(), u.ID, StatusPending,
	)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return ErrNotFound
	}
	return nil
}

// UpdateLastLogin updates last_login_at.
func (s *Store) UpdateLastLogin(userID int64) error {
	_, err := s.db.Exec(`UPDATE users SET last_login_at = ? WHERE id = ?`, now(), userID)
	return err
}

// SetUserStatus sets a user's status (active/disabled/pending).
func (s *Store) SetUserStatus(id int64, status string) error {
	res, err := s.db.Exec(`UPDATE users SET status = ?, updated_at = ? WHERE id = ?`, status, now(), id)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return ErrNotFound
	}
	return nil
}

// UpdateVault applies a new blob with optimistic locking (CAS on the revision).
// Returns the new revision or ErrConflict.
func (s *Store) UpdateVault(userID, baseRevision int64, blob, nonce []byte, keyWrapped, keyWrappedRecov []byte) (int64, error) {
	res, err := s.db.Exec(
		`UPDATE users SET vault_blob = ?, vault_nonce = ?, vault_key_wrapped = COALESCE(?, vault_key_wrapped),
		        vault_key_wrapped_recov = COALESCE(?, vault_key_wrapped_recov),
		        vault_revision = vault_revision + 1, updated_at = ?
		 WHERE id = ? AND vault_revision = ?`,
		blob, nonce, keyWrapped, keyWrappedRecov, now(), userID, baseRevision,
	)
	if err != nil {
		return 0, err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return 0, ErrConflict
	}
	return baseRevision + 1, nil
}

// UpdateAuthMaterial updates in a single transaction the auth hash,
// the KDF parameters, the wrapped keys and the recovery hash, revoking all sessions.
// If burnRecovery is true, the recovery hash is set to the new value (or cleared if nil).
func (s *Store) UpdateAuthMaterial(u *User, kdf KDFParams, burnRecovery bool) error {
	kp, err := json.Marshal(kdf)
	if err != nil {
		return err
	}
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	var recoveryHash any
	if u.RecoveryHash != nil {
		recoveryHash = u.RecoveryHash
	}
	_, err = tx.Exec(
		`UPDATE users SET auth_hash = ?, salt = ?, kdf_algorithm = ?, kdf_params = ?,
		        vault_key_wrapped = ?, vault_key_wrapped_recov = ?, recovery_hash = ?, updated_at = ?
		 WHERE id = ?`,
		u.AuthHash, u.Salt, u.KDFAlgorithm, string(kp), u.VaultKeyWrapped,
		u.VaultKeyWrappedRecov, recoveryHash, now(), u.ID,
	)
	if err != nil {
		return err
	}
	if burnRecovery {
		if _, err := tx.Exec(`DELETE FROM sessions WHERE user_id = ?`, u.ID); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// CreateSession creates a new session and returns the plaintext token.
func (s *Store) CreateSession(userID int64, deviceName string, ttl time.Duration) (string, error) {
	token, err := crypto.RandomBytes(32)
	if err != nil {
		return "", err
	}
	tokenStr := crypto.EncodeBase64(token)
	_, err = s.db.Exec(
		`INSERT INTO sessions (user_id, token_hash, device_name, created_at, expires_at) VALUES (?, ?, ?, ?, ?)`,
		userID, hashToken([]byte(tokenStr)), deviceName, now(), time.Now().UTC().Add(ttl).Format(time.RFC3339),
	)
	if err != nil {
		return "", err
	}
	return tokenStr, nil
}

// GetUserBySessionToken retrieves the user associated with a valid session token.
func (s *Store) GetUserBySessionToken(token string) (*User, error) {
	var u User
	var expires string
	err := s.db.QueryRow(
		`SELECT u.id, u.username, u.status, u.salt, u.kdf_algorithm, u.kdf_params,
		        u.auth_hash, u.recovery_hash, u.vault_key_wrapped, u.vault_key_wrapped_recov,
		        u.vault_blob, u.vault_nonce, u.vault_revision, u.created_at, u.updated_at, u.last_login_at,
		        s.expires_at
		 FROM sessions s JOIN users u ON u.id = s.user_id
		 WHERE s.token_hash = ?`, hashToken([]byte(token))).Scan(
		&u.ID, &u.Username, &u.Status, &u.Salt, &u.KDFAlgorithm, &u.kdfParamsRaw,
		&u.AuthHash, &u.RecoveryHash, &u.VaultKeyWrapped, &u.VaultKeyWrappedRecov,
		&u.VaultBlob, &u.VaultNonce, &u.VaultRevision, &u.createdAtRaw, &u.updatedAtRaw, &u.lastLoginRaw,
		&expires,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, ErrNotFound
		}
		return nil, err
	}
	exp, err := parseTime(expires)
	if err != nil {
		// A malformed expiry is treated as an invalid session.
		s.DeleteSession(token)
		return nil, ErrNotFound
	}
	if time.Now().UTC().After(exp) {
		s.DeleteSession(token)
		return nil, ErrNotFound
	}
	if err := u.parseExtras(); err != nil {
		return nil, err
	}
	return &u, nil
}

// DeleteSession revokes a session.
func (s *Store) DeleteSession(token string) error {
	_, err := s.db.Exec(`DELETE FROM sessions WHERE token_hash = ?`, hashToken([]byte(token)))
	return err
}

// DeleteAllSessions revokes all sessions of a user.
func (s *Store) DeleteAllSessions(userID int64) error {
	_, err := s.db.Exec(`DELETE FROM sessions WHERE user_id = ?`, userID)
	return err
}

func (s *Store) scanUser(row *sql.Row) (*User, error) {
	var u User
	err := row.Scan(
		&u.ID, &u.Username, &u.Status, &u.InviteTokenHash, &u.Salt, &u.KDFAlgorithm,
		&u.kdfParamsRaw, &u.AuthHash, &u.RecoveryHash, &u.VaultKeyWrapped,
		&u.VaultKeyWrappedRecov, &u.VaultBlob, &u.VaultNonce, &u.VaultRevision,
		&u.createdAtRaw, &u.updatedAtRaw, &u.lastLoginRaw,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, ErrNotFound
		}
		return nil, err
	}
	if err := u.parseExtras(); err != nil {
		return nil, err
	}
	return &u, nil
}

func (u *User) parseExtras() error {
	if u.kdfParamsRaw == "" {
		u.KDFParams = KDFParams{MemoryKiB: 65536, Iterations: 3, Parallelism: 4}
		return nil
	}
	if err := json.Unmarshal([]byte(u.kdfParamsRaw), &u.KDFParams); err != nil {
		return fmt.Errorf("invalid kdf_params for %s: %w", u.Username, err)
	}
	var err error
	if u.CreatedAt, err = parseTime(u.createdAtRaw); err != nil {
		return err
	}
	if u.UpdatedAt, err = parseTime(u.updatedAtRaw); err != nil {
		return err
	}
	if u.lastLoginRaw.Valid {
		if u.LastLoginAt, err = parseTime(u.lastLoginRaw.String); err != nil {
			return err
		}
	}
	return nil
}

func hashToken(t []byte) []byte {
	return crypto.SHA256(t)
}

func now() string { return time.Now().UTC().Format(time.RFC3339Nano) }

func parseTime(s string) (time.Time, error) {
	if s == "" {
		return time.Time{}, nil
	}
	t, err := time.Parse(time.RFC3339Nano, s)
	if err != nil {
		return time.Time{}, fmt.Errorf("invalid timestamp %q: %w", s, err)
	}
	return t, nil
}
