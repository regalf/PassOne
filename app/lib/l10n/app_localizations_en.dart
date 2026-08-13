// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'PassOne';

  @override
  String get signIn => 'Sign in';

  @override
  String get createAccount => 'Create an account';

  @override
  String get forgotRecovery => 'Forgot password? Use recovery key';

  @override
  String get serverLabel => 'Server address';

  @override
  String get serverHint => 'https://passone.example.com';

  @override
  String get serverIntro => 'Enter the address of your PassOne server';

  @override
  String get connectButton => 'Continue';

  @override
  String get changeServer => 'Change server';

  @override
  String get invalidServerUrl => 'Enter a valid server address.';

  @override
  String get serverUnreachable =>
      'Could not reach the server. Check the address and your connection.';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get tagline => 'End-to-end password manager';

  @override
  String get fillAllFields => 'Fill in all fields.';

  @override
  String get fillUserPass => 'Fill in username and password.';

  @override
  String get passwordTooShort =>
      'The password must be at least 8 characters long.';

  @override
  String get passwordsDiffer => 'Passwords do not match.';

  @override
  String get invalidCredentials => 'Invalid credentials.';

  @override
  String unexpectedError(Object error) {
    return 'Unexpected error: $error';
  }

  @override
  String errorPrefix(Object error) {
    return 'Error: $error';
  }

  @override
  String syncError(Object error) {
    return 'Sync error: $error';
  }

  @override
  String get registerTitle => 'Create account';

  @override
  String get registerFirstAccess => 'First access';

  @override
  String get inviteToken => 'Invite token (provided by the admin)';

  @override
  String get masterPassword => 'Master password';

  @override
  String get confirmMasterPassword => 'Confirm master password';

  @override
  String get wantRecovery => 'Generate a recovery key (recommended)';

  @override
  String get wantRecoverySub =>
      'Allows you to recover access if you forget your password';

  @override
  String get submitRegistration => 'Create account';

  @override
  String get recoveryKeyTitle => 'Save your recovery key';

  @override
  String get recoveryKeyBody =>
      'This key is shown only ONCE. You need it to recover access if you forget your password. Copy it and store it in a safe place.';

  @override
  String get savedKeyButton => 'I saved the key';

  @override
  String get recoveryGeneratedNotice =>
      'Recovery key generated: save it now or you will not be able to recover your account.';

  @override
  String get unlockTitle => 'Vault locked';

  @override
  String get enterPassword => 'Enter your password.';

  @override
  String get invalidPassword => 'Invalid password.';

  @override
  String get bioCanceled => 'Authentication canceled: use your password.';

  @override
  String get bioUnavailable =>
      'Biometrics unavailable: use your password or re-enable biometric unlock in settings.';

  @override
  String get unlockButton => 'Unlock';

  @override
  String get logout => 'Log out';

  @override
  String get unlockBiometric => 'Unlock with fingerprint';

  @override
  String get recoverTitle => 'Account recovery';

  @override
  String get recoverIntro =>
      'Use your recovery key to reset your master password without losing your vault.';

  @override
  String get recoveryKey => 'Recovery key';

  @override
  String get newMasterPassword => 'New master password';

  @override
  String get confirmPassword => 'Confirm password';

  @override
  String get wantNewRecovery => 'Generate a new recovery key';

  @override
  String get invalidRecoveryKey => 'Invalid recovery key.';

  @override
  String get recoverButton => 'Recover account';

  @override
  String get newRecoveryKeyTitle => 'New recovery key';

  @override
  String get newRecoveryKeyBody =>
      'The old key has been burned. This is your new recovery key: store it in a safe place, it will only be shown now.';

  @override
  String get searchVault => 'Search vault…';

  @override
  String get tabVault => 'Vault';

  @override
  String get tabPasswords => 'Passwords';

  @override
  String get tabTotp => 'TOTP';

  @override
  String get tabSsh => 'SSH';

  @override
  String get newFab => 'New';

  @override
  String get addFab => 'Add';

  @override
  String get lockTooltip => 'Lock';

  @override
  String get settingsTooltip => 'Settings';

  @override
  String get sectionCategories => 'Categories';

  @override
  String get folders => 'Folders';

  @override
  String get folder => 'Folder';

  @override
  String get noFolder => 'No folder';

  @override
  String get newFolder => 'New folder';

  @override
  String get renameFolder => 'Rename folder';

  @override
  String get deleteFolder => 'Delete folder';

  @override
  String get deleteFolderTitle => 'Delete the folder?';

  @override
  String deleteFolderBody(Object name) {
    return '\"$name\" will be removed. Its entries stay in the vault without a folder.';
  }

  @override
  String get addFolder => 'Add';

  @override
  String get folderName => 'Folder name';

  @override
  String get noFolders =>
      'No folders yet. Create one to organize your entries.';

  @override
  String get emptyFolder => 'No entries in this folder.';

  @override
  String entryCount(Object count) {
    return '$count items';
  }

  @override
  String get emptyVault =>
      'The vault is empty.\nPress \"New\" to add an entry.';

  @override
  String get emptyTotp => 'No TOTP codes.\nPress \"Add\" to scan a QR.';

  @override
  String get emptySsh => 'No SSH keys.\nPress \"New\" to add a key.';

  @override
  String noResults(Object query) {
    return 'No results for \"$query\".';
  }

  @override
  String get copyUsername => 'Copy username';

  @override
  String get copyPassword => 'Copy password';

  @override
  String get copyCode => 'Copy code';

  @override
  String get copyPrivateKey => 'Copy private key';

  @override
  String get copyPublicKey => 'Copy public key';

  @override
  String get copyPassphrase => 'Copy passphrase';

  @override
  String get delete => 'Delete';

  @override
  String get deleteEntryTitle => 'Delete the entry?';

  @override
  String deleteEntryBody(Object name) {
    return '\"$name\" will be permanently removed.';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get usernameCopied => 'Username copied';

  @override
  String get passwordCopied => 'Password copied';

  @override
  String get codeCopied => 'Code copied';

  @override
  String get privateKeyCopied => 'Private key copied';

  @override
  String get publicKeyCopied => 'Public key copied';

  @override
  String get passphraseCopied => 'Passphrase copied';

  @override
  String get totpNotes => 'Two-factor code';

  @override
  String secondsLeft(Object left) {
    return '$left s';
  }

  @override
  String get newEntryTitle => 'New entry';

  @override
  String get editEntryTitle => 'Edit entry';

  @override
  String get save => 'Save';

  @override
  String get name => 'Name';

  @override
  String get url => 'URL';

  @override
  String get usernameEmail => 'Username / Email';

  @override
  String get notes => 'Notes';

  @override
  String get generate => 'Generate';

  @override
  String get copy => 'Copy';

  @override
  String get enterName => 'Enter a name.';

  @override
  String get newSshTitle => 'New SSH key';

  @override
  String get editSshTitle => 'Edit SSH key';

  @override
  String get host => 'Host';

  @override
  String get privateKey => 'Private key';

  @override
  String get publicKey => 'Public key';

  @override
  String get passphrase => 'Passphrase';

  @override
  String get importFromFile => 'Import from file…';

  @override
  String get sshImportFailed => 'Could not read the file.';

  @override
  String keyImported(Object file) {
    return 'Imported $file';
  }

  @override
  String get generatorTitle => 'Password generator';

  @override
  String get length => 'Length';

  @override
  String get uppercase => 'Uppercase';

  @override
  String get lowercase => 'Lowercase';

  @override
  String get numbers => 'Numbers';

  @override
  String get symbols => 'Symbols';

  @override
  String get regenerate => 'Regenerate';

  @override
  String get use => 'Use';

  @override
  String get scanQrTitle => 'Scan the QR code';

  @override
  String get scannerGuide =>
      'Point at the QR from Google Authenticator or your 2FA app';

  @override
  String cameraUnavailable(Object error) {
    return 'Camera unavailable: $error';
  }

  @override
  String get close => 'Close';

  @override
  String get totpTestTitle => 'TOTP test';

  @override
  String get totpScanHint => 'Scan this QR with \"Add\" in the TOTP tab';

  @override
  String get verifyField => 'Code to verify';

  @override
  String get verify => 'Verify';

  @override
  String get codeCorrect => 'Correct code';

  @override
  String get codeWrong => 'Wrong code';

  @override
  String get seedLabel => 'Seed (Base32)';

  @override
  String get newSeed => 'Generate a new seed';

  @override
  String get addTotpToVault => 'Add TOTP to vault';

  @override
  String get addedToVault => 'Added to vault';

  @override
  String get seedAlreadyInVault => 'Seed already in vault';

  @override
  String get totpAdded => 'TOTP added to vault';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get autofill => 'Autofill';

  @override
  String get autofillSub =>
      'When enabled, PassOne fills saved logins in other apps and browsers and captures new passwords to store in the vault.';

  @override
  String get autofillEnabled => 'Active';

  @override
  String get autofillDisabled => 'Disabled — tap to open the system settings';

  @override
  String get autofillChecking => 'Checking…';

  @override
  String autofillImported(Object count) {
    return '$count passwords imported from autofill';
  }

  @override
  String get sectionGeneral => 'General';

  @override
  String get biometricEnabled => 'Fingerprint unlock enabled';

  @override
  String get biometricDisabled => 'Fingerprint unlock disabled';

  @override
  String biometricEnableFailed(Object error) {
    return 'Unable to enable: $error';
  }

  @override
  String get sectionServer => 'Server';

  @override
  String get serverAddress => 'Server address';

  @override
  String get notConfigured => 'Not configured';

  @override
  String get sectionSecurity => 'Security';

  @override
  String get autoLock => 'Auto lock';

  @override
  String autoLockSub(Object label) {
    return 'The vault locks after $label';
  }

  @override
  String get alwaysKeepOpen => 'Keep the vault always open?';

  @override
  String get alwaysKeepOpenWarning =>
      'HIGHLY DISCOURAGED: anyone with access to the device could read your passwords. Prefer a short timeout.';

  @override
  String get proceedAnyway => 'Proceed anyway';

  @override
  String get biometricAccess => 'Fingerprint unlock';

  @override
  String get biometricSub =>
      'Unlock the vault without typing the master password';

  @override
  String get recoveryKeyStatus => 'Recovery key';

  @override
  String get active => 'Active';

  @override
  String get notActive => 'Not active';

  @override
  String get changeMasterPassword => 'Change master password';

  @override
  String get sectionSession => 'Session';

  @override
  String get logoutSub => 'Revoke this session';

  @override
  String get logoutAll => 'Log out of all devices';

  @override
  String get logoutAllSub => 'Revoke all sessions';

  @override
  String get revokeAllTitle => 'Revoke all sessions?';

  @override
  String get revokeAllBody => 'You will need to sign in again on every device.';

  @override
  String get revoke => 'Revoke';

  @override
  String get sectionDeveloper => 'Developer';

  @override
  String get testTotp => 'TOTP test';

  @override
  String get testTotpSub =>
      'Generate a TOTP QR and verify the code produced by the app';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get italian => 'Italian';

  @override
  String get english => 'English';

  @override
  String get lockAlways => 'Always';

  @override
  String lockMinutes(Object minutes) {
    return '$minutes minutes';
  }

  @override
  String get recoveryActive => 'Recovery key active';

  @override
  String get recoveryNotActive => 'Recovery key not active';

  @override
  String get rotateRecovery => 'Rotate recovery key';

  @override
  String get rotateRecoverySub => 'Generate a new key';

  @override
  String get disableRecovery => 'Disable recovery key';

  @override
  String get disableRecoverySub =>
      'You will no longer be able to recover your account';

  @override
  String get enableRecovery => 'Enable recovery key';

  @override
  String get enableRecoverySub => 'Requires your current password';

  @override
  String get disableRecoveryTitle => 'Disable the recovery key?';

  @override
  String get disableRecoveryBody =>
      'If you forget your password, the vault will be wiped. Proceed?';

  @override
  String get confirmMaster => 'Confirm with your master password';

  @override
  String get confirm => 'Confirm';

  @override
  String get operationCompleted => 'Operation completed';

  @override
  String get wrongPassword => 'Invalid password';

  @override
  String get saveNewRecoveryTitle => 'Save the new recovery key';

  @override
  String get shownOnce => 'Shown only once.';

  @override
  String get currentPassword => 'Current password';

  @override
  String get newPassword => 'New password';

  @override
  String get change => 'Change';

  @override
  String get passwordMinLength =>
      'The new password must be at least 8 characters long';

  @override
  String get passwordsDontMatch => 'Passwords do not match';

  @override
  String get passwordChanged => 'Password changed';

  @override
  String get currentPasswordInvalid => 'Current password is invalid';

  @override
  String get exportTitle => 'Export vault';

  @override
  String get exportWarning =>
      'JSON and CSV are plain text; the PassOne file is encrypted with a password.';

  @override
  String get exportFormatLabel => 'Format';

  @override
  String get exportPassone => 'PassOne (encrypted)';

  @override
  String get exportJson => 'JSON';

  @override
  String get exportCsv => 'CSV';

  @override
  String get exportPasswordTitle => 'Protect the export';

  @override
  String get exportPasswordPrompt =>
      'Choose a password to encrypt this file. It will be required to import it.';

  @override
  String get exportPasswordLabel => 'Encryption password';

  @override
  String get exportPasswordConfirmLabel => 'Confirm password';

  @override
  String get exportPasswordRequired => 'Enter a password.';

  @override
  String exportSaved(Object path) {
    return 'Export saved to $path';
  }

  @override
  String get sectionData => 'Data';

  @override
  String get exportVault => 'Export vault';

  @override
  String get exportSub => 'JSON, CSV or encrypted PassOne file';

  @override
  String get importVault => 'Import vault';

  @override
  String get importSub => 'From JSON, CSV or encrypted PassOne file';

  @override
  String get importTitle => 'Import vault';

  @override
  String get importIntro =>
      'Choose a file format, then pick a PassOne (.passone), JSON or CSV file. Existing entries are merged and synced.';

  @override
  String get importFormatLabel => 'File format';

  @override
  String get importFormatAuto => 'Auto (recommended)';

  @override
  String get importFormatPassone => 'PassOne (encrypted)';

  @override
  String get importFormatJson => 'JSON';

  @override
  String get importFormatCsv => 'CSV';

  @override
  String get importFormatBitwarden => 'Bitwarden CSV';

  @override
  String get importPassoneTitle => 'Unlock import';

  @override
  String get importPassonePrompt =>
      'This file is encrypted. Enter the password used to create it.';

  @override
  String get importPassoneLabel => 'File password';

  @override
  String get importPassoneRequired => 'Enter the file password.';

  @override
  String get importWrongPassword => 'Wrong password or corrupted file.';

  @override
  String importFailed(Object error) {
    return 'Import failed: $error';
  }

  @override
  String importedCount(Object imported, Object total) {
    return 'Imported $imported items ($total total).';
  }

  @override
  String get chooseFile => 'Choose file';

  @override
  String get jsonFormatUnknown => 'Unknown JSON format';
}
