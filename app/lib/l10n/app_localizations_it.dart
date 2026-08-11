// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appTitle => 'PassOne';

  @override
  String get signIn => 'Accedi';

  @override
  String get createAccount => 'Crea un account';

  @override
  String get forgotRecovery => 'Password dimenticata? Usa la recovery key';

  @override
  String get serverLabel => 'Indirizzo server';

  @override
  String get serverHint => 'https://passone.example.com';

  @override
  String get username => 'Nome utente';

  @override
  String get password => 'Password';

  @override
  String get tagline => 'Password manager end-to-end';

  @override
  String get fillAllFields => 'Compila tutti i campi.';

  @override
  String get fillUserPass => 'Inserisci nome utente e password.';

  @override
  String get passwordTooShort => 'La password deve avere almeno 8 caratteri.';

  @override
  String get passwordsDiffer => 'Le password non coincidono.';

  @override
  String get invalidCredentials => 'Credenziali non valide.';

  @override
  String unexpectedError(Object error) {
    return 'Errore imprevisto: $error';
  }

  @override
  String errorPrefix(Object error) {
    return 'Errore: $error';
  }

  @override
  String syncError(Object error) {
    return 'Errore di sincronizzazione: $error';
  }

  @override
  String get registerTitle => 'Crea account';

  @override
  String get registerFirstAccess => 'Primo accesso';

  @override
  String get inviteToken => 'Token di invito (fornito dall\'amministratore)';

  @override
  String get masterPassword => 'Password principale';

  @override
  String get confirmMasterPassword => 'Conferma password principale';

  @override
  String get wantRecovery => 'Genera una recovery key (consigliato)';

  @override
  String get wantRecoverySub =>
      'Permette di recuperare l\'accesso se dimentichi la password';

  @override
  String get submitRegistration => 'Crea account';

  @override
  String get recoveryKeyTitle => 'Salva la tua recovery key';

  @override
  String get recoveryKeyBody =>
      'Questa chiave viene mostrata una sola volta. Ti serve per recuperare l\'accesso se dimentichi la password. Copiala e conservala in un luogo sicuro.';

  @override
  String get savedKeyButton => 'Ho salvato la chiave';

  @override
  String get recoveryGeneratedNotice =>
      'Recovery key generata: salvala subito o non potrai più recuperare l\'account.';

  @override
  String get unlockTitle => 'Vault bloccato';

  @override
  String get enterPassword => 'Inserisci la password.';

  @override
  String get invalidPassword => 'Password non valida.';

  @override
  String get bioCanceled => 'Autenticazione annullata: usa la password.';

  @override
  String get bioUnavailable =>
      'Biometria non disponibile: usa la password o riattivala nelle impostazioni.';

  @override
  String get unlockButton => 'Sblocca';

  @override
  String get logout => 'Esci (logout)';

  @override
  String get unlockBiometric => 'Sblocca con impronta';

  @override
  String get recoverTitle => 'Recupero account';

  @override
  String get recoverIntro =>
      'Usa la tua recovery key per resettare la password principale senza perdere il vault.';

  @override
  String get recoveryKey => 'Recovery key';

  @override
  String get newMasterPassword => 'Nuova password principale';

  @override
  String get confirmPassword => 'Conferma password';

  @override
  String get wantNewRecovery => 'Genera una nuova recovery key';

  @override
  String get invalidRecoveryKey => 'Recovery key non valida.';

  @override
  String get recoverButton => 'Recupera account';

  @override
  String get newRecoveryKeyTitle => 'Nuova recovery key';

  @override
  String get newRecoveryKeyBody =>
      'La vecchia chiave è stata bruciata. Questa è la tua nuova recovery key: conservala in un luogo sicuro, verrà mostrata solo ora.';

  @override
  String get searchVault => 'Cerca nel vault…';

  @override
  String get tabPasswords => 'Password';

  @override
  String get tabTotp => 'TOTP';

  @override
  String get newFab => 'Nuova';

  @override
  String get addFab => 'Aggiungi';

  @override
  String get lockTooltip => 'Blocca';

  @override
  String get settingsTooltip => 'Impostazioni';

  @override
  String get emptyVault =>
      'Il vault è vuoto.\nPremi \"Nuova\" per aggiungere una voce.';

  @override
  String get emptyTotp =>
      'Nessun codice TOTP.\nPremi \"Aggiungi\" per scansionare un QR.';

  @override
  String noResults(Object query) {
    return 'Nessun risultato per \"$query\".';
  }

  @override
  String get copyUsername => 'Copia nome utente';

  @override
  String get copyPassword => 'Copia password';

  @override
  String get copyCode => 'Copia codice';

  @override
  String get delete => 'Elimina';

  @override
  String get deleteEntryTitle => 'Eliminare la voce?';

  @override
  String deleteEntryBody(Object name) {
    return '\"$name\" verrà rimossa definitivamente.';
  }

  @override
  String get cancel => 'Annulla';

  @override
  String get usernameCopied => 'Nome utente copiato';

  @override
  String get passwordCopied => 'Password copiata';

  @override
  String get codeCopied => 'Codice copiato';

  @override
  String get totpNotes => 'Codice a due fattori';

  @override
  String secondsLeft(Object left) {
    return '$left s';
  }

  @override
  String get newEntryTitle => 'Nuova voce';

  @override
  String get editEntryTitle => 'Modifica voce';

  @override
  String get save => 'Salva';

  @override
  String get name => 'Nome';

  @override
  String get url => 'URL';

  @override
  String get usernameEmail => 'Nome utente / Email';

  @override
  String get notes => 'Note';

  @override
  String get generate => 'Genera';

  @override
  String get copy => 'Copia';

  @override
  String get enterName => 'Inserisci un nome.';

  @override
  String get generatorTitle => 'Generatore password';

  @override
  String get length => 'Lunghezza';

  @override
  String get uppercase => 'Maiuscole';

  @override
  String get lowercase => 'Minuscole';

  @override
  String get numbers => 'Numeri';

  @override
  String get symbols => 'Simboli';

  @override
  String get regenerate => 'Rigenera';

  @override
  String get use => 'Usa';

  @override
  String get scanQrTitle => 'Scansiona il QR code';

  @override
  String get scannerGuide =>
      'Inquadra il QR di Google Authenticator o della tua app 2FA';

  @override
  String cameraUnavailable(Object error) {
    return 'Fotocamera non disponibile: $error';
  }

  @override
  String get close => 'Chiudi';

  @override
  String get totpTestTitle => 'Test TOTP';

  @override
  String get totpScanHint =>
      'Scansiona questo QR con \"Aggiungi\" nella scheda TOTP';

  @override
  String get verifyField => 'Codice da verificare';

  @override
  String get verify => 'Verifica';

  @override
  String get codeCorrect => 'Codice corretto';

  @override
  String get codeWrong => 'Codice errato';

  @override
  String get seedLabel => 'Seed (Base32)';

  @override
  String get newSeed => 'Genera un nuovo seed';

  @override
  String get addTotpToVault => 'Aggiungi TOTP al vault';

  @override
  String get addedToVault => 'Aggiunto al vault';

  @override
  String get seedAlreadyInVault => 'Seed già presente nel vault';

  @override
  String get totpAdded => 'TOTP aggiunto al vault';

  @override
  String get settingsTitle => 'Impostazioni';

  @override
  String get sectionGeneral => 'Generale';

  @override
  String get biometricEnabled => 'Accesso con impronta attivato';

  @override
  String get biometricDisabled => 'Accesso con impronta disattivato';

  @override
  String biometricEnableFailed(Object error) {
    return 'Impossibile attivare: $error';
  }

  @override
  String get sectionServer => 'Server';

  @override
  String get serverAddress => 'Indirizzo server';

  @override
  String get notConfigured => 'Non configurato';

  @override
  String get sectionSecurity => 'Sicurezza';

  @override
  String get autoLock => 'Blocco automatico';

  @override
  String autoLockSub(Object label) {
    return 'Il vault si blocca dopo $label';
  }

  @override
  String get alwaysKeepOpen => 'Lasciare il vault sempre aperto?';

  @override
  String get alwaysKeepOpenWarning =>
      'ALTAMENTE SCONSIGLIATO: chiunque abbia accesso al dispositivo potrebbe leggere le tue password. Preferisci un timeout breve.';

  @override
  String get proceedAnyway => 'Procedi comunque';

  @override
  String get biometricAccess => 'Sblocco con impronta';

  @override
  String get biometricSub =>
      'Sblocca il vault senza digitare la password principale';

  @override
  String get recoveryKeyStatus => 'Recovery key';

  @override
  String get active => 'Attiva';

  @override
  String get notActive => 'Non attiva';

  @override
  String get changeMasterPassword => 'Cambia password principale';

  @override
  String get sectionSession => 'Sessione';

  @override
  String get logoutSub => 'Revoca questa sessione';

  @override
  String get logoutAll => 'Esci da tutti i dispositivi';

  @override
  String get logoutAllSub => 'Revoca tutte le sessioni';

  @override
  String get revokeAllTitle => 'Revocare tutte le sessioni?';

  @override
  String get revokeAllBody => 'Dovrai accedere di nuovo su ogni dispositivo.';

  @override
  String get revoke => 'Revoca';

  @override
  String get sectionDeveloper => 'Sviluppatore';

  @override
  String get testTotp => 'Test TOTP';

  @override
  String get testTotpSub =>
      'Genera un QR TOTP e verifica il codice prodotto dall\'app';

  @override
  String get language => 'Lingua';

  @override
  String get languageSystem => 'Sistema';

  @override
  String get italian => 'Italiano';

  @override
  String get english => 'English';

  @override
  String get lockAlways => 'Sempre (sconsigliato)';

  @override
  String lockMinutes(Object minutes) {
    return '$minutes minuti';
  }

  @override
  String get recoveryActive => 'Recovery key attiva';

  @override
  String get recoveryNotActive => 'Recovery key non attiva';

  @override
  String get rotateRecovery => 'Ruota la recovery key';

  @override
  String get rotateRecoverySub => 'Genera una nuova chiave';

  @override
  String get disableRecovery => 'Disabilita la recovery key';

  @override
  String get disableRecoverySub => 'Non potrai più recuperare l\'account';

  @override
  String get enableRecovery => 'Attiva la recovery key';

  @override
  String get enableRecoverySub => 'Richiede la password corrente';

  @override
  String get disableRecoveryTitle => 'Disabilitare la recovery key?';

  @override
  String get disableRecoveryBody =>
      'Se dimentichi la password, il vault verrà cancellato. Continuare?';

  @override
  String get confirmMaster => 'Conferma con la password principale';

  @override
  String get confirm => 'Conferma';

  @override
  String get operationCompleted => 'Operazione completata';

  @override
  String get wrongPassword => 'Password non valida';

  @override
  String get saveNewRecoveryTitle => 'Salva la nuova recovery key';

  @override
  String get shownOnce => 'Mostrata solo una volta.';

  @override
  String get currentPassword => 'Password attuale';

  @override
  String get newPassword => 'Nuova password';

  @override
  String get change => 'Cambia';

  @override
  String get passwordMinLength =>
      'La nuova password deve avere almeno 8 caratteri';

  @override
  String get passwordsDontMatch => 'Le password non coincidono';

  @override
  String get passwordChanged => 'Password cambiata';

  @override
  String get currentPasswordInvalid => 'La password attuale non è valida';

  @override
  String get exportTitle => 'Esporta vault';

  @override
  String get exportWarning =>
      'I dati esportati sono in chiaro: conservali in un luogo sicuro.';

  @override
  String get jsonFull => 'JSON (completo)';

  @override
  String exportSaved(Object path) {
    return 'Esportazione salvata in $path';
  }

  @override
  String get sectionData => 'Dati';

  @override
  String get exportVault => 'Esporta vault';

  @override
  String get exportSub => 'JSON o CSV, in chiaro';

  @override
  String get importVault => 'Importa vault';

  @override
  String get importSub => 'Da file JSON o CSV';

  @override
  String get importTitle => 'Importa vault';

  @override
  String get importIntro =>
      'Scegli un file JSON (esportazione PassOne) o CSV con colonne: name,url,username,password,notes. Le voci esistenti vengono unite.';

  @override
  String importFailed(Object error) {
    return 'Import fallito: $error';
  }

  @override
  String importedCount(Object imported, Object total) {
    return 'Importati $imported elementi ($total in totale).';
  }

  @override
  String get chooseFile => 'Scegli file';

  @override
  String get jsonFormatUnknown => 'Formato JSON sconosciuto';
}
