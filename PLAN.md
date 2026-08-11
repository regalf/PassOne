# PassOne — Piano di progetto

Password manager **self-hostable** con crittografia **end-to-end**.

## Obiettivo

Server hostabile liberamente (anche senza HTTPS, ma con HTTPS consigliato), gestibile via
**web UI** oppure in modalità **headless** (CLI). App **desktop** (Flutter) e, successivamente,
**Android** (stesso codebase Flutter). Nessuna password viene mai salvata sul server; i dati di
ogni utente sono criptati lato client e il server non può decifrarli.

## Stack

| Componente | Tecnologia | Motivo |
|---|---|---|
| Server | Go 1.26+, `modernc.org/sqlite` (senza CGO), `net/http` | Singolo binario, self-host facile |
| App client | Flutter (Dart) | Un solo codebase per desktop + Android |
| Stato app | Riverpod | Moderno, testabile |
| Crypto client | `argon2_ffi` (fallback PBKDF2 puro Dart), `cryptography` (AES-256-GCM) | KDF robusto + AEAD |
| Storage locale | `drift` (SQLite) + `shared_preferences` | Cache offline + impostazioni |

## Architettura

```
PassOne/
├── PLAN.md
├── README.md
├── server/                 # Go, singolo binario `passone`
│   ├── cmd/passone/        # serve + CLI (sottocomandi)
│   ├── internal/
│   │   ├── api/            # REST handlers + rate limiting + middleware
│   │   ├── auth/           # sessioni token opachi, verifica auth-hash
│   │   ├── store/          # SQLite: utenti, sessioni, blob vault
│   │   ├── config/         # YAML + env
│   │   └── crypto/         # Argon2id verify, AEAD, generazione chiavi
│   └── webui/              # admin SPA embedded (embed.FS)
└── app/                    # Flutter (desktop + Android)
    └── lib/
        ├── crypto/         # KDF, AEAD, envelope vault-key, recovery key
        ├── api/            # client REST + sync con revision
        ├── state/          # Riverpod: sessione, vault, lock timer
        └── ui/             # onboarding, setup, lock, vault, entry, generator, settings
```

## Modello di sicurezza

### Crittografia end-to-end

1. **KDF**: `KEK = Argon2id(master_password, salt)` — derivata SOLO sul client, mai inviata.
2. **Vault**: generata una `vault_key` casuale (256 bit). I dati del vault si criptano con
   AES-256-GCM usando `vault_key`. Nonce casuale per ogni blob.
3. **Envelope**: `vault_key` viene avvolta con `AEAD(KEK, vault_key)`. Cambiare password =
   riavvolgere solo la chiave, senza ri-criptare i dati.
4. **Doppio wrapper (recovery key)**: se l'utente attiva la recovery key, la `vault_key` viene
   avvolta anche con `AEAD(recovery_key, vault_key)`.
5. **Auth senza password**: il client invia `authHash = SHA-256(KEK)`. Il server salva SOLO
   questo hash. Non conosce né la password né la chiave → non può decifrare nulla.
6. **Recovery hash**: il server salva `SHA-256(recovery_key)` per verificare il reset senza
   mai conoscere la chiave.

### Server storage (per utente)

`username, status, salt, kdf_params, auth_hash, recovery_hash (opz), vault_key_wrapped (KEK),
vault_key_wrapped_recovery (opz), vault_blob, vault_nonce, vault_revision, created/updated, last_login`

### Trasporto

- **HTTPS**: configurazione consigliata (anche via reverse proxy es. Caddy).
- **HTTP puro**: il blob è AEAD-criptato, quindi funziona; il server logga un avviso.
  Restano esposti metadata (username, timestamps, dimensioni) e brute-force offline
  dell'authHash → mitigato con rate limiting.

## Lock / unlock (lato client)

- Il **lock è solo client-side**: al timeout la `KEK`/`vault_key` vengono cancellate dalla
  memoria e l'app mostra la lock screen. La sessione col server resta valida (lock ≠ logout).
- Timeout configurabile per dispositivo: **1 / 2 / 5 / 10 minuti / sempre** (con avviso
  "ALTAMENTE SCONSIGLIATO").
- Impostazione salvata in `shared_preferences`; timer gestito dallo stato Riverpod.

## Flussi utente

### Registrazione / setup
1. **Via app** (se abilitata nel config server): l'utente sceglie username + master password.
   Il client genera salt, KEK, `vault_key`, authHash, avvolge e fa `POST /auth/setup`.
   Alla creazione può attivare la **recovery key**.
2. **Creato da admin** (CLI o web UI): utente in stato `pending` + *invite token*. L'app al
   primo accesso chiede username + master password + invite token → `POST /auth/setup`.
   La password non passa mai dall'admin.

### Recovery key (monouso)
- All'iscrizione (opzionale) il client genera una `recovery_key` a 256 bit e la mostra UNA
  sola volta, richiedendo conferma di salvataggio.
- **Reset password con recovery key**: `POST /auth/recover` — il client invia
  `SHA-256(recovery_key)` + nuova password. Il server verifica l'hash e in **un'unica
  transazione atomica** sostituisce auth-hash, salt/KDF, chiavi avvolte; **brucia** i dati di
  recovery precedenti. Le sessioni vengono **tutte revocate**. Il client mostra la NUOVA
  recovery key (se l'utente la riattiva) con conferma di salvataggio.
- **Rotazione volontaria** della recovery key (impostazioni) — stesso meccanismo, senza reset.
- Chi non attiva la recovery key: reset password = **vault azzerato** (come Bitwarden).

### Sync multi-dispositivo
- `GET/PUT /vault` con `vault_revision` incrementale lato server.
- **Optimistic locking**: il PUT porta la revision di base → mismatch = `409` → il client
  rifetcha e applica **last-write-wins**.
- Cache locale del blob per accesso offline; sync al primo unlock in linea.

## API v1

| Metodo | Path | Descrizione |
|---|---|---|
| POST | `/auth/setup` | Registrazione o primo accesso (invite token) |
| POST | `/auth/login` | Login → token opaco (hash in DB, expiry 30gg) |
| POST | `/auth/logout` | Revoca sessione corrente |
| POST | `/auth/logout-all` | Revoca tutte le sessioni |
| POST | `/auth/change-password` | Cambio master password (re-wrap con KEK + recovery) |
| POST | `/auth/recover` | Reset con recovery key (atomico, brucia chiave, revoca sessioni) |
| GET | `/vault` | Recupera blob + revision |
| PUT | `/vault` | Aggiorna blob (optimistic locking, `409` su conflitto) |
| GET | `/admin/users` | Lista utenti (admin) |
| POST | `/admin/users` | Crea utente `pending` → restituisce invite token (admin) |
| DELETE | `/admin/users/{id}` | Disabilita/elimina utente (admin) |
| POST | `/admin/users/{id}/reset-invite` | Rigenera invite token (admin) |
| GET | `/health` | Health check |

Token: opaco a 32 byte, memorizzato come SHA-256 in DB, expiry 30gg, con `device_name`
per la gestione "logout all devices".

## CLI del server (singolo binario `passone`)

```
passone serve [--config config.yaml] [--no-ui]
passone user create <username>          # → stampa invite token
passone user list
passone user disable <username>
passone user reset-invite <username>
passone config init
passone backup --out backup.json        # include blob (criptati)
```

## Web UI admin (Fase 3)

SPA minimal embedded nel binario (`embed.FS`), servita da `/admin/` quando attiva
(flag config; `--no-ui` la disabilita). Funzioni:
- lista utenti (stato pending/active), creazione utente + mostra invite token,
  disable/reset-invite, riepilogo configurazione.
- Nessuna funzionalità crittografica: solo gestione utenti e configurazione.

## Funzionalità v1 (app)

- Voci username/password + note (CRUD)
- Generatore password (lunghezza, maiuscole/minuscole, numeri, simboli)
- Import/export CSV/JSON
- Sync multi-dispositivo + accesso offline
- Cambio master password
- Gestione dispositivi / logout all devices
- Lock automatico (1/2/5/10 min / sempre)
- Recovery key opzionale + rotazione
- **POSTICIPATO**: TOTP/2FA, vault condivisi, estensioni browser

## Fasi

1. **Fase 1 — Preliminare**: installazione Flutter SDK (stabile, Linux) + toolchain.
2. **Fase 2 — Server Go**: config, SQLite, auth (setup/login/sessioni), vault GET/PUT,
   CLI utenti, rate limiting, avviso HTTPS, test `httptest`.
3. **Fase 3 — Web UI admin**: gestione utenti minimal embedded.
4. **Fase 4 — App Flutter core**: onboarding (URL server), setup/login, lock/unlock con
   timer, CRUD voci, generatore password, sync + cache offline.
5. **Fase 5 — App Flutter finiture**: import/export, cambio password, recovery key,
   logout all, settings, packaging desktop + APK.
6. **Fase 6 — Docs**: setup, reverse proxy HTTPS, limiti v1.

## Stato avanzamento

- [x] Fase 1 (Flutter 3.44.9 installato, telemetria disabilitata)
- [x] Fase 2 (server Go: `go test ./...` verdi, smoke test su porta di test superato)
- [x] Fase 3 (web UI admin embedded, servita su `/admin/`)
- [x] Fase 4 (app: auth, lock/unlock con timer, CRUD voci, generatore, sync LWW + cache offline)
- [x] Fase 5a (app: import/export JSON/CSV, cambio master password, recovery key
      attiva/ruota/disattiva, logout all, settings; `flutter analyze` pulito,
      `flutter test` verde, `flutter build linux --release` ok)
- [ ] Fase 5b (Android APK: manca il toolchain SDK)
- [x] Fase 6 (docs: README con setup rapido, reverse proxy HTTPS, note sicurezza)

## Decisioni aperte / note

- KDF di default: **Argon2id** (t=3, m=64MiB, p=4), parametri salvati per-utente nel DB
  (migrabili). Fallback PBKDF2-HMAC-SHA256 (600k iter) se le lib native danno problemi.
- DB v1: **solo SQLite** (file unico, facile backup). Interfaccia per estendere a Postgres.
- Registrazione via app disabilitabile da config (`allow_registration: false`).
- Rate limiting: per-IP su login e recover, in-memory per v1.
