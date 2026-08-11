# PassOne

Self-hostable password manager with **end-to-end encryption** (Go server + Flutter app).
The server never sees your passwords: it only stores hashes (SHA-256 of the derived key) and
AES-256-GCM encrypted blobs; no data can be decrypted server-side.

## Quick start — server

Prerequisites: Go 1.26+.

```bash
cd server

# 1. Build the single binary
go build -o passone ./cmd/passone

# 2. Generate the configuration (creates config.yaml with a random admin token)
./passone config init

# 3. Start the server (default: http://127.0.0.1:8321)
./passone serve
```

On first start, if `admin_token` is not in `config.yaml`, one is generated and printed: **save it**.

### Creating a user

```bash
# Creates the user (status "pending") and prints the one-time invite token
./passone user create <username>

# Or, if direct registration is enabled (allow_registration: true),
# users can sign up directly from the app.
```

Other useful commands:

```bash
./passone user list
./passone user disable <username>
./passone user reset-invite <username>
./passone backup --out backup.json    # encrypted blobs + auth material
```

### Admin web UI

With the web UI enabled (default), open `http://<server>:8321/admin/` and enter the **admin token**:
here you can create users and view invite tokens.

### Listening on the local network / publicly

By default the server listens only on `127.0.0.1`. To expose it, edit `config.yaml`
(or use `--addr`):

```yaml
addr: "0.0.0.0:8321"
allow_registration: false   # recommended: manage users via invite
```

### HTTPS (recommended)

The server supports direct TLS (`tls_cert`/`tls_key` in config.yaml) or a reverse proxy.
With Caddy:

```
example.com {
    reverse_proxy 127.0.0.1:8321
}
```

Without HTTPS the server logs a warning: the transport is not encrypted, but the data stays
unreadable (AEAD) to anyone who intercepts it; only metadata (username, timestamps) is exposed.

## Quick start — desktop app (Linux)

Prerequisites: Flutter SDK (see Phase 1).

```bash
cd app
flutter pub get

# Release build
flutter build linux --release

# Run
./build/linux/x64/release/bundle/passone_app
```

### First access

1. Enter the **server URL** (e.g. `https://passone.example.com` or `http://192.168.1.10:8321`).
2. If the user already exists (created by an admin): username + master password + **invite token**.
   If direct registration is active: just username + master password.
3. Enable the **recovery key** (recommended): it is shown only once, save it.
4. The vault is ready: add your first entries with the **New** button.

The vault locks automatically (1/2/5/10 minutes) and unlocks with the master password,
even offline (local cache).

## Android

Building the APK requires the Android SDK. With the toolchain installed:

```bash
cd app
flutter build apk --release
```

## Backup and recovery

- `passone backup` exports the encrypted blobs and the authentication material to a JSON file:
  keep it on a safe medium.
- To restore, the data must be re-inserted into the SQLite database (the `passone.db` file) — a
  dedicated command will be available in the future.

## Security notes

- The **recovery key** lets you reset a forgotten password **only if it was enabled**.
  Without it, a forgotten password = wiped vault (like Bitwarden).
- If enabled, the recovery key is **burned after every use** and each reset revokes all
  sessions.
- Auto-lock is client-side: it protects against device theft, not against the server.
