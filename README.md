# PassOne

Password manager **self-hostable** con crittografia **end-to-end** (server Go + app Flutter).
Il server non conosce mai le password: salva solo hash (SHA-256 della chiave derivata) e blob
criptati AES-256-GCM; nessun dato può essere decifrato lato server.

## Setup veloce — server

Prerequisiti: Go 1.26+.

```bash
cd server

# 1. Compila il binario singolo
go build -o passone ./cmd/passone

# 2. Genera la configurazione (crea config.yaml con un admin token casuale)
./passone config init

# 3. Avvia il server (default: http://127.0.0.1:8321)
./passone serve
```

Al primo avvio, se l'`admin_token` non è in `config.yaml`, viene generato e stampato: **salvalo**.

### Creare un utente

```bash
# Crea l'utente (stato "pending") e stampa l'invite token monouso
./passone user create <username>

# Oppure, se la registrazione diretta è abilitata (allow_registration: true),
# l'utente può iscriversi direttamente dall'app.
```

Altri comandi utili:

```bash
./passone user list
./passone user disable <username>
./passone user reset-invite <username>
./passone backup --out backup.json    # blob criptati + materiale auth
```

### Web UI admin

Con la web UI abilitata (default), apri `http://<server>:8321/admin/` e inserisci l'**admin token**:
qui puoi creare utenti e vedere gli invite token.

### Ascolto su rete locale / pubblico

Per impostazione predefinita il server ascolta solo su `127.0.0.1`. Per esporlo, modifica
`config.yaml` (o usa `--addr`):

```yaml
addr: "0.0.0.0:8321"
allow_registration: false   # consigliato: gestisci gli utenti via invite
```

### HTTPS (consigliato)

Il server supporta TLS diretto (`tls_cert`/`tls_key` in config.yaml) oppure un reverse proxy.
Con Caddy:

```
example.com {
    reverse_proxy 127.0.0.1:8321
}
```

Senza HTTPS il server logga un avviso: il trasporto non è cifrato ma i dati restano
illeggibili (AEAD) a chi intercetta; restano esposti solo metadati (username, timestamps).

## Setup veloce — app desktop (Linux)

Prerequisiti: Flutter SDK (vedi Fase 1).

```bash
cd app
flutter pub get

# Build release
flutter build linux --release

# Esegui
./build/linux/x64/release/bundle/passone_app
```

### Primo accesso

1. Inserisci l'**URL del server** (es. `https://passone.example.com` o `http://192.168.1.10:8321`).
2. Se l'utente esiste già (creato da admin): username + master password + **invite token**.
   Se la registrazione diretta è attiva: basta username + master password.
3. Attiva la **recovery key** (consigliato): ti verrà mostrata una sola volta, salvala.
4. Il vault è pronto: aggiungi le prime voci con il pulsante **Nuova**.

Il vault si blocca automaticamente (1/2/5/10 minuti) e si sblocca con la master password,
anche offline (cache locale).

## Android

La build APK richiede l'Android SDK. Con il toolchain installato:

```bash
cd app
flutter build apk --release
```

## Backup e recupero

- `passone backup` esporta in un file JSON i blob criptati e il materiale di autenticazione:
  conservalo su un supporto sicuro.
- Per ripristinare, i dati vanno reinseriti nel database SQLite (il file `passone.db`) — in
  futuro sarà disponibile un comando dedicato.

## Note di sicurezza

- La **recovery key** permette di reimpostare la password smarrita **solo se attivata**.
  Senza di essa, la password dimenticata = vault azzerato (come Bitwarden).
- Se attivata, la recovery key viene **bruciata dopo ogni uso** e ogni reset revoca tutte
  le sessioni.
- Il blocco automatico è client-side: protegge dal furto del dispositivo, non dal server.

## Architettura e piano

Dettagli in [PLAN.md](PLAN.md): modello di crittografia, API v1, CLI, web UI e stato avanzamento.
