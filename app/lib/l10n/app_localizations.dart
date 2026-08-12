import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_it.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('it'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'PassOne'**
  String get appTitle;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create an account'**
  String get createAccount;

  /// No description provided for @forgotRecovery.
  ///
  /// In en, this message translates to:
  /// **'Forgot password? Use recovery key'**
  String get forgotRecovery;

  /// No description provided for @serverLabel.
  ///
  /// In en, this message translates to:
  /// **'Server address'**
  String get serverLabel;

  /// No description provided for @serverHint.
  ///
  /// In en, this message translates to:
  /// **'https://passone.example.com'**
  String get serverHint;

  /// No description provided for @serverIntro.
  ///
  /// In en, this message translates to:
  /// **'Enter the address of your PassOne server'**
  String get serverIntro;

  /// No description provided for @connectButton.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get connectButton;

  /// No description provided for @changeServer.
  ///
  /// In en, this message translates to:
  /// **'Change server'**
  String get changeServer;

  /// No description provided for @invalidServerUrl.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid server address.'**
  String get invalidServerUrl;

  /// No description provided for @serverUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the server. Check the address and your connection.'**
  String get serverUnreachable;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @tagline.
  ///
  /// In en, this message translates to:
  /// **'End-to-end password manager'**
  String get tagline;

  /// No description provided for @fillAllFields.
  ///
  /// In en, this message translates to:
  /// **'Fill in all fields.'**
  String get fillAllFields;

  /// No description provided for @fillUserPass.
  ///
  /// In en, this message translates to:
  /// **'Fill in username and password.'**
  String get fillUserPass;

  /// No description provided for @passwordTooShort.
  ///
  /// In en, this message translates to:
  /// **'The password must be at least 8 characters long.'**
  String get passwordTooShort;

  /// No description provided for @passwordsDiffer.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match.'**
  String get passwordsDiffer;

  /// No description provided for @invalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'Invalid credentials.'**
  String get invalidCredentials;

  /// No description provided for @unexpectedError.
  ///
  /// In en, this message translates to:
  /// **'Unexpected error: {error}'**
  String unexpectedError(Object error);

  /// No description provided for @errorPrefix.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorPrefix(Object error);

  /// No description provided for @syncError.
  ///
  /// In en, this message translates to:
  /// **'Sync error: {error}'**
  String syncError(Object error);

  /// No description provided for @registerTitle.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get registerTitle;

  /// No description provided for @registerFirstAccess.
  ///
  /// In en, this message translates to:
  /// **'First access'**
  String get registerFirstAccess;

  /// No description provided for @inviteToken.
  ///
  /// In en, this message translates to:
  /// **'Invite token (provided by the admin)'**
  String get inviteToken;

  /// No description provided for @masterPassword.
  ///
  /// In en, this message translates to:
  /// **'Master password'**
  String get masterPassword;

  /// No description provided for @confirmMasterPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm master password'**
  String get confirmMasterPassword;

  /// No description provided for @wantRecovery.
  ///
  /// In en, this message translates to:
  /// **'Generate a recovery key (recommended)'**
  String get wantRecovery;

  /// No description provided for @wantRecoverySub.
  ///
  /// In en, this message translates to:
  /// **'Allows you to recover access if you forget your password'**
  String get wantRecoverySub;

  /// No description provided for @submitRegistration.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get submitRegistration;

  /// No description provided for @recoveryKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'Save your recovery key'**
  String get recoveryKeyTitle;

  /// No description provided for @recoveryKeyBody.
  ///
  /// In en, this message translates to:
  /// **'This key is shown only ONCE. You need it to recover access if you forget your password. Copy it and store it in a safe place.'**
  String get recoveryKeyBody;

  /// No description provided for @savedKeyButton.
  ///
  /// In en, this message translates to:
  /// **'I saved the key'**
  String get savedKeyButton;

  /// No description provided for @recoveryGeneratedNotice.
  ///
  /// In en, this message translates to:
  /// **'Recovery key generated: save it now or you will not be able to recover your account.'**
  String get recoveryGeneratedNotice;

  /// No description provided for @unlockTitle.
  ///
  /// In en, this message translates to:
  /// **'Vault locked'**
  String get unlockTitle;

  /// No description provided for @enterPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter your password.'**
  String get enterPassword;

  /// No description provided for @invalidPassword.
  ///
  /// In en, this message translates to:
  /// **'Invalid password.'**
  String get invalidPassword;

  /// No description provided for @bioCanceled.
  ///
  /// In en, this message translates to:
  /// **'Authentication canceled: use your password.'**
  String get bioCanceled;

  /// No description provided for @bioUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Biometrics unavailable: use your password or re-enable biometric unlock in settings.'**
  String get bioUnavailable;

  /// No description provided for @unlockButton.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlockButton;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logout;

  /// No description provided for @unlockBiometric.
  ///
  /// In en, this message translates to:
  /// **'Unlock with fingerprint'**
  String get unlockBiometric;

  /// No description provided for @recoverTitle.
  ///
  /// In en, this message translates to:
  /// **'Account recovery'**
  String get recoverTitle;

  /// No description provided for @recoverIntro.
  ///
  /// In en, this message translates to:
  /// **'Use your recovery key to reset your master password without losing your vault.'**
  String get recoverIntro;

  /// No description provided for @recoveryKey.
  ///
  /// In en, this message translates to:
  /// **'Recovery key'**
  String get recoveryKey;

  /// No description provided for @newMasterPassword.
  ///
  /// In en, this message translates to:
  /// **'New master password'**
  String get newMasterPassword;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get confirmPassword;

  /// No description provided for @wantNewRecovery.
  ///
  /// In en, this message translates to:
  /// **'Generate a new recovery key'**
  String get wantNewRecovery;

  /// No description provided for @invalidRecoveryKey.
  ///
  /// In en, this message translates to:
  /// **'Invalid recovery key.'**
  String get invalidRecoveryKey;

  /// No description provided for @recoverButton.
  ///
  /// In en, this message translates to:
  /// **'Recover account'**
  String get recoverButton;

  /// No description provided for @newRecoveryKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'New recovery key'**
  String get newRecoveryKeyTitle;

  /// No description provided for @newRecoveryKeyBody.
  ///
  /// In en, this message translates to:
  /// **'The old key has been burned. This is your new recovery key: store it in a safe place, it will only be shown now.'**
  String get newRecoveryKeyBody;

  /// No description provided for @searchVault.
  ///
  /// In en, this message translates to:
  /// **'Search vault…'**
  String get searchVault;

  /// No description provided for @tabPasswords.
  ///
  /// In en, this message translates to:
  /// **'Passwords'**
  String get tabPasswords;

  /// No description provided for @tabTotp.
  ///
  /// In en, this message translates to:
  /// **'TOTP'**
  String get tabTotp;

  /// No description provided for @tabSsh.
  ///
  /// In en, this message translates to:
  /// **'SSH'**
  String get tabSsh;

  /// No description provided for @newFab.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get newFab;

  /// No description provided for @addFab.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addFab;

  /// No description provided for @lockTooltip.
  ///
  /// In en, this message translates to:
  /// **'Lock'**
  String get lockTooltip;

  /// No description provided for @settingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTooltip;

  /// No description provided for @emptyVault.
  ///
  /// In en, this message translates to:
  /// **'The vault is empty.\nPress \"New\" to add an entry.'**
  String get emptyVault;

  /// No description provided for @emptyTotp.
  ///
  /// In en, this message translates to:
  /// **'No TOTP codes.\nPress \"Add\" to scan a QR.'**
  String get emptyTotp;

  /// No description provided for @emptySsh.
  ///
  /// In en, this message translates to:
  /// **'No SSH keys.\nPress \"New\" to add a key.'**
  String get emptySsh;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No results for \"{query}\".'**
  String noResults(Object query);

  /// No description provided for @copyUsername.
  ///
  /// In en, this message translates to:
  /// **'Copy username'**
  String get copyUsername;

  /// No description provided for @copyPassword.
  ///
  /// In en, this message translates to:
  /// **'Copy password'**
  String get copyPassword;

  /// No description provided for @copyCode.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get copyCode;

  /// No description provided for @copyPrivateKey.
  ///
  /// In en, this message translates to:
  /// **'Copy private key'**
  String get copyPrivateKey;

  /// No description provided for @copyPublicKey.
  ///
  /// In en, this message translates to:
  /// **'Copy public key'**
  String get copyPublicKey;

  /// No description provided for @copyPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Copy passphrase'**
  String get copyPassphrase;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deleteEntryTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete the entry?'**
  String get deleteEntryTitle;

  /// No description provided for @deleteEntryBody.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" will be permanently removed.'**
  String deleteEntryBody(Object name);

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @usernameCopied.
  ///
  /// In en, this message translates to:
  /// **'Username copied'**
  String get usernameCopied;

  /// No description provided for @passwordCopied.
  ///
  /// In en, this message translates to:
  /// **'Password copied'**
  String get passwordCopied;

  /// No description provided for @codeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get codeCopied;

  /// No description provided for @privateKeyCopied.
  ///
  /// In en, this message translates to:
  /// **'Private key copied'**
  String get privateKeyCopied;

  /// No description provided for @publicKeyCopied.
  ///
  /// In en, this message translates to:
  /// **'Public key copied'**
  String get publicKeyCopied;

  /// No description provided for @passphraseCopied.
  ///
  /// In en, this message translates to:
  /// **'Passphrase copied'**
  String get passphraseCopied;

  /// No description provided for @totpNotes.
  ///
  /// In en, this message translates to:
  /// **'Two-factor code'**
  String get totpNotes;

  /// No description provided for @secondsLeft.
  ///
  /// In en, this message translates to:
  /// **'{left} s'**
  String secondsLeft(Object left);

  /// No description provided for @newEntryTitle.
  ///
  /// In en, this message translates to:
  /// **'New entry'**
  String get newEntryTitle;

  /// No description provided for @editEntryTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit entry'**
  String get editEntryTitle;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @url.
  ///
  /// In en, this message translates to:
  /// **'URL'**
  String get url;

  /// No description provided for @usernameEmail.
  ///
  /// In en, this message translates to:
  /// **'Username / Email'**
  String get usernameEmail;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @generate.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get generate;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @enterName.
  ///
  /// In en, this message translates to:
  /// **'Enter a name.'**
  String get enterName;

  /// No description provided for @newSshTitle.
  ///
  /// In en, this message translates to:
  /// **'New SSH key'**
  String get newSshTitle;

  /// No description provided for @editSshTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit SSH key'**
  String get editSshTitle;

  /// No description provided for @host.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get host;

  /// No description provided for @privateKey.
  ///
  /// In en, this message translates to:
  /// **'Private key'**
  String get privateKey;

  /// No description provided for @publicKey.
  ///
  /// In en, this message translates to:
  /// **'Public key'**
  String get publicKey;

  /// No description provided for @passphrase.
  ///
  /// In en, this message translates to:
  /// **'Passphrase'**
  String get passphrase;

  /// No description provided for @importFromFile.
  ///
  /// In en, this message translates to:
  /// **'Import from file…'**
  String get importFromFile;

  /// No description provided for @sshImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read the file.'**
  String get sshImportFailed;

  /// No description provided for @keyImported.
  ///
  /// In en, this message translates to:
  /// **'Imported {file}'**
  String keyImported(Object file);

  /// No description provided for @generatorTitle.
  ///
  /// In en, this message translates to:
  /// **'Password generator'**
  String get generatorTitle;

  /// No description provided for @length.
  ///
  /// In en, this message translates to:
  /// **'Length'**
  String get length;

  /// No description provided for @uppercase.
  ///
  /// In en, this message translates to:
  /// **'Uppercase'**
  String get uppercase;

  /// No description provided for @lowercase.
  ///
  /// In en, this message translates to:
  /// **'Lowercase'**
  String get lowercase;

  /// No description provided for @numbers.
  ///
  /// In en, this message translates to:
  /// **'Numbers'**
  String get numbers;

  /// No description provided for @symbols.
  ///
  /// In en, this message translates to:
  /// **'Symbols'**
  String get symbols;

  /// No description provided for @regenerate.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get regenerate;

  /// No description provided for @use.
  ///
  /// In en, this message translates to:
  /// **'Use'**
  String get use;

  /// No description provided for @scanQrTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code'**
  String get scanQrTitle;

  /// No description provided for @scannerGuide.
  ///
  /// In en, this message translates to:
  /// **'Point at the QR from Google Authenticator or your 2FA app'**
  String get scannerGuide;

  /// No description provided for @cameraUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Camera unavailable: {error}'**
  String cameraUnavailable(Object error);

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @totpTestTitle.
  ///
  /// In en, this message translates to:
  /// **'TOTP test'**
  String get totpTestTitle;

  /// No description provided for @totpScanHint.
  ///
  /// In en, this message translates to:
  /// **'Scan this QR with \"Add\" in the TOTP tab'**
  String get totpScanHint;

  /// No description provided for @verifyField.
  ///
  /// In en, this message translates to:
  /// **'Code to verify'**
  String get verifyField;

  /// No description provided for @verify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verify;

  /// No description provided for @codeCorrect.
  ///
  /// In en, this message translates to:
  /// **'Correct code'**
  String get codeCorrect;

  /// No description provided for @codeWrong.
  ///
  /// In en, this message translates to:
  /// **'Wrong code'**
  String get codeWrong;

  /// No description provided for @seedLabel.
  ///
  /// In en, this message translates to:
  /// **'Seed (Base32)'**
  String get seedLabel;

  /// No description provided for @newSeed.
  ///
  /// In en, this message translates to:
  /// **'Generate a new seed'**
  String get newSeed;

  /// No description provided for @addTotpToVault.
  ///
  /// In en, this message translates to:
  /// **'Add TOTP to vault'**
  String get addTotpToVault;

  /// No description provided for @addedToVault.
  ///
  /// In en, this message translates to:
  /// **'Added to vault'**
  String get addedToVault;

  /// No description provided for @seedAlreadyInVault.
  ///
  /// In en, this message translates to:
  /// **'Seed already in vault'**
  String get seedAlreadyInVault;

  /// No description provided for @totpAdded.
  ///
  /// In en, this message translates to:
  /// **'TOTP added to vault'**
  String get totpAdded;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @sectionGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get sectionGeneral;

  /// No description provided for @biometricEnabled.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint unlock enabled'**
  String get biometricEnabled;

  /// No description provided for @biometricDisabled.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint unlock disabled'**
  String get biometricDisabled;

  /// No description provided for @biometricEnableFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to enable: {error}'**
  String biometricEnableFailed(Object error);

  /// No description provided for @sectionServer.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get sectionServer;

  /// No description provided for @serverAddress.
  ///
  /// In en, this message translates to:
  /// **'Server address'**
  String get serverAddress;

  /// No description provided for @notConfigured.
  ///
  /// In en, this message translates to:
  /// **'Not configured'**
  String get notConfigured;

  /// No description provided for @sectionSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get sectionSecurity;

  /// No description provided for @autoLock.
  ///
  /// In en, this message translates to:
  /// **'Auto lock'**
  String get autoLock;

  /// No description provided for @autoLockSub.
  ///
  /// In en, this message translates to:
  /// **'The vault locks after {label}'**
  String autoLockSub(Object label);

  /// No description provided for @alwaysKeepOpen.
  ///
  /// In en, this message translates to:
  /// **'Keep the vault always open?'**
  String get alwaysKeepOpen;

  /// No description provided for @alwaysKeepOpenWarning.
  ///
  /// In en, this message translates to:
  /// **'HIGHLY DISCOURAGED: anyone with access to the device could read your passwords. Prefer a short timeout.'**
  String get alwaysKeepOpenWarning;

  /// No description provided for @proceedAnyway.
  ///
  /// In en, this message translates to:
  /// **'Proceed anyway'**
  String get proceedAnyway;

  /// No description provided for @biometricAccess.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint unlock'**
  String get biometricAccess;

  /// No description provided for @biometricSub.
  ///
  /// In en, this message translates to:
  /// **'Unlock the vault without typing the master password'**
  String get biometricSub;

  /// No description provided for @recoveryKeyStatus.
  ///
  /// In en, this message translates to:
  /// **'Recovery key'**
  String get recoveryKeyStatus;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @notActive.
  ///
  /// In en, this message translates to:
  /// **'Not active'**
  String get notActive;

  /// No description provided for @changeMasterPassword.
  ///
  /// In en, this message translates to:
  /// **'Change master password'**
  String get changeMasterPassword;

  /// No description provided for @sectionSession.
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get sectionSession;

  /// No description provided for @logoutSub.
  ///
  /// In en, this message translates to:
  /// **'Revoke this session'**
  String get logoutSub;

  /// No description provided for @logoutAll.
  ///
  /// In en, this message translates to:
  /// **'Log out of all devices'**
  String get logoutAll;

  /// No description provided for @logoutAllSub.
  ///
  /// In en, this message translates to:
  /// **'Revoke all sessions'**
  String get logoutAllSub;

  /// No description provided for @revokeAllTitle.
  ///
  /// In en, this message translates to:
  /// **'Revoke all sessions?'**
  String get revokeAllTitle;

  /// No description provided for @revokeAllBody.
  ///
  /// In en, this message translates to:
  /// **'You will need to sign in again on every device.'**
  String get revokeAllBody;

  /// No description provided for @revoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get revoke;

  /// No description provided for @sectionDeveloper.
  ///
  /// In en, this message translates to:
  /// **'Developer'**
  String get sectionDeveloper;

  /// No description provided for @testTotp.
  ///
  /// In en, this message translates to:
  /// **'TOTP test'**
  String get testTotp;

  /// No description provided for @testTotpSub.
  ///
  /// In en, this message translates to:
  /// **'Generate a TOTP QR and verify the code produced by the app'**
  String get testTotpSub;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @italian.
  ///
  /// In en, this message translates to:
  /// **'Italian'**
  String get italian;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @lockAlways.
  ///
  /// In en, this message translates to:
  /// **'Always (not recommended)'**
  String get lockAlways;

  /// No description provided for @lockMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} minutes'**
  String lockMinutes(Object minutes);

  /// No description provided for @recoveryActive.
  ///
  /// In en, this message translates to:
  /// **'Recovery key active'**
  String get recoveryActive;

  /// No description provided for @recoveryNotActive.
  ///
  /// In en, this message translates to:
  /// **'Recovery key not active'**
  String get recoveryNotActive;

  /// No description provided for @rotateRecovery.
  ///
  /// In en, this message translates to:
  /// **'Rotate recovery key'**
  String get rotateRecovery;

  /// No description provided for @rotateRecoverySub.
  ///
  /// In en, this message translates to:
  /// **'Generate a new key'**
  String get rotateRecoverySub;

  /// No description provided for @disableRecovery.
  ///
  /// In en, this message translates to:
  /// **'Disable recovery key'**
  String get disableRecovery;

  /// No description provided for @disableRecoverySub.
  ///
  /// In en, this message translates to:
  /// **'You will no longer be able to recover your account'**
  String get disableRecoverySub;

  /// No description provided for @enableRecovery.
  ///
  /// In en, this message translates to:
  /// **'Enable recovery key'**
  String get enableRecovery;

  /// No description provided for @enableRecoverySub.
  ///
  /// In en, this message translates to:
  /// **'Requires your current password'**
  String get enableRecoverySub;

  /// No description provided for @disableRecoveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Disable the recovery key?'**
  String get disableRecoveryTitle;

  /// No description provided for @disableRecoveryBody.
  ///
  /// In en, this message translates to:
  /// **'If you forget your password, the vault will be wiped. Proceed?'**
  String get disableRecoveryBody;

  /// No description provided for @confirmMaster.
  ///
  /// In en, this message translates to:
  /// **'Confirm with your master password'**
  String get confirmMaster;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @operationCompleted.
  ///
  /// In en, this message translates to:
  /// **'Operation completed'**
  String get operationCompleted;

  /// No description provided for @wrongPassword.
  ///
  /// In en, this message translates to:
  /// **'Invalid password'**
  String get wrongPassword;

  /// No description provided for @saveNewRecoveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Save the new recovery key'**
  String get saveNewRecoveryTitle;

  /// No description provided for @shownOnce.
  ///
  /// In en, this message translates to:
  /// **'Shown only once.'**
  String get shownOnce;

  /// No description provided for @currentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get currentPassword;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get newPassword;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @passwordMinLength.
  ///
  /// In en, this message translates to:
  /// **'The new password must be at least 8 characters long'**
  String get passwordMinLength;

  /// No description provided for @passwordsDontMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordsDontMatch;

  /// No description provided for @passwordChanged.
  ///
  /// In en, this message translates to:
  /// **'Password changed'**
  String get passwordChanged;

  /// No description provided for @currentPasswordInvalid.
  ///
  /// In en, this message translates to:
  /// **'Current password is invalid'**
  String get currentPasswordInvalid;

  /// No description provided for @exportTitle.
  ///
  /// In en, this message translates to:
  /// **'Export vault'**
  String get exportTitle;

  /// No description provided for @exportWarning.
  ///
  /// In en, this message translates to:
  /// **'JSON and CSV are plain text; the PassOne file is encrypted with a password.'**
  String get exportWarning;

  /// No description provided for @exportFormatLabel.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get exportFormatLabel;

  /// No description provided for @exportPassone.
  ///
  /// In en, this message translates to:
  /// **'PassOne (encrypted)'**
  String get exportPassone;

  /// No description provided for @exportJson.
  ///
  /// In en, this message translates to:
  /// **'JSON'**
  String get exportJson;

  /// No description provided for @exportCsv.
  ///
  /// In en, this message translates to:
  /// **'CSV'**
  String get exportCsv;

  /// No description provided for @exportPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Protect the export'**
  String get exportPasswordTitle;

  /// No description provided for @exportPasswordPrompt.
  ///
  /// In en, this message translates to:
  /// **'Choose a password to encrypt this file. It will be required to import it.'**
  String get exportPasswordPrompt;

  /// No description provided for @exportPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Encryption password'**
  String get exportPasswordLabel;

  /// No description provided for @exportPasswordConfirmLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get exportPasswordConfirmLabel;

  /// No description provided for @exportPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a password.'**
  String get exportPasswordRequired;

  /// No description provided for @exportSaved.
  ///
  /// In en, this message translates to:
  /// **'Export saved to {path}'**
  String exportSaved(Object path);

  /// No description provided for @sectionData.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get sectionData;

  /// No description provided for @exportVault.
  ///
  /// In en, this message translates to:
  /// **'Export vault'**
  String get exportVault;

  /// No description provided for @exportSub.
  ///
  /// In en, this message translates to:
  /// **'JSON, CSV or encrypted PassOne file'**
  String get exportSub;

  /// No description provided for @importVault.
  ///
  /// In en, this message translates to:
  /// **'Import vault'**
  String get importVault;

  /// No description provided for @importSub.
  ///
  /// In en, this message translates to:
  /// **'From JSON, CSV or encrypted PassOne file'**
  String get importSub;

  /// No description provided for @importTitle.
  ///
  /// In en, this message translates to:
  /// **'Import vault'**
  String get importTitle;

  /// No description provided for @importIntro.
  ///
  /// In en, this message translates to:
  /// **'Choose a file format, then pick a PassOne (.passone), JSON or CSV file. Existing entries are merged and synced.'**
  String get importIntro;

  /// No description provided for @importFormatLabel.
  ///
  /// In en, this message translates to:
  /// **'File format'**
  String get importFormatLabel;

  /// No description provided for @importFormatAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto (recommended)'**
  String get importFormatAuto;

  /// No description provided for @importFormatPassone.
  ///
  /// In en, this message translates to:
  /// **'PassOne (encrypted)'**
  String get importFormatPassone;

  /// No description provided for @importFormatJson.
  ///
  /// In en, this message translates to:
  /// **'JSON'**
  String get importFormatJson;

  /// No description provided for @importFormatCsv.
  ///
  /// In en, this message translates to:
  /// **'CSV'**
  String get importFormatCsv;

  /// No description provided for @importFormatBitwarden.
  ///
  /// In en, this message translates to:
  /// **'Bitwarden CSV'**
  String get importFormatBitwarden;

  /// No description provided for @importPassoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock import'**
  String get importPassoneTitle;

  /// No description provided for @importPassonePrompt.
  ///
  /// In en, this message translates to:
  /// **'This file is encrypted. Enter the password used to create it.'**
  String get importPassonePrompt;

  /// No description provided for @importPassoneLabel.
  ///
  /// In en, this message translates to:
  /// **'File password'**
  String get importPassoneLabel;

  /// No description provided for @importPassoneRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the file password.'**
  String get importPassoneRequired;

  /// No description provided for @importWrongPassword.
  ///
  /// In en, this message translates to:
  /// **'Wrong password or corrupted file.'**
  String get importWrongPassword;

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String importFailed(Object error);

  /// No description provided for @importedCount.
  ///
  /// In en, this message translates to:
  /// **'Imported {imported} items ({total} total).'**
  String importedCount(Object imported, Object total);

  /// No description provided for @chooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose file'**
  String get chooseFile;

  /// No description provided for @jsonFormatUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown JSON format'**
  String get jsonFormatUnknown;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'it'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'it':
      return AppLocalizationsIt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
