# Changelog

All notable changes to this project are documented in this file.

## [3.5.0] - 2026-08-14

### Added
- **Passkey support (Credential Manager)**:
  - Android credential provider service (`PasskeyProviderService`) exposing vault passkeys to the platform credential picker.
  - Passkey creation flow with on-device key generation, biometric user verification and vault storage.
  - Passkey authentication flow returning a signed assertion to the relying party.
  - Passkey entries in the vault with dedicated UI and automatic matching by relying party ID.
  - `androidx.credentials` integration and biometric gating via a dedicated `PasskeyAuthActivity`.
- **Android autofill service**:
  - New autofill service with manual-request fill, single-field datasets and keyboard incognito support.
  - Richer dropdown UX with an auth gate and a locked-vault unlock prompt.
- **Build script** (`scripts/build.py`): now builds and packages both debug and release Android APKs.

### Fixed
- **Passkey assertion signature format**: ECDSA assertions are now signed in ASN.1 DER form, as required by verifiers such as go-webauthn (webauthn.io). Previously the raw `r||s` form was rejected with "could not verify authentication signature". Verified end-to-end against a local go-webauthn relying party and webauthn.io on both Chrome and Firefox.
- **Autofill crashes**: return a null response when no fillable field is present, avoiding a `FillResponse.build()` `IllegalStateException`; always send `SaveInfo` so the system reliably offers the save prompt.

### Changed
- All Android `Log.*` calls routed through a `PLog` wrapper gated behind `BuildConfig.DEBUG`, so no diagnostic or potentially sensitive data is logged in release builds.
