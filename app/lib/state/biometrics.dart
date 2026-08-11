import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Risultato di una lettura della bioKey dal Keystore.
enum BiometricReadResult {
  /// Chiave letta e biometria superata.
  success,

  /// Prompt annullato o impronta non valida (utente può riprovare/annullare).
  canceled,

  /// Nessuna bioKey disponibile o chiave invalidata (es. impronte modificate).
  unavailable,
}

/// Accesso biometrico: disponibilità (local_auth) e bioKey nell'Android
/// Keystore protetta da autenticazione a ogni lettura (flutter_secure_storage
/// con [AndroidOptions.biometric]). Funziona solo su Android.
class BiometricService {
  static const _key = 'passone_bio_key';
  static const _options = AndroidOptions.biometric(
    enforceBiometrics: true,
    biometricType: AndroidBiometricType.strongBiometricOnly,
    biometricPromptTitle: 'Unlock PassOne',
    biometricPromptSubtitle: 'Use your fingerprint to open the vault',
    biometricPromptNegativeButton: 'Use password',
  );

  final LocalAuthentication _auth;
  final FlutterSecureStorage _storage;

  BiometricService({LocalAuthentication? auth, FlutterSecureStorage? storage})
      : _auth = auth ?? LocalAuthentication(),
        _storage = storage ?? const FlutterSecureStorage();

  /// True solo su Android con biometria forte registrata (es. impronta).
  Future<bool> isAvailable() async {
    if (!Platform.isAndroid) return false;
    try {
      if (!await _auth.isDeviceSupported()) return false;
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Salva la [bioKey] nel Keystore; il prompt biometrico NON scatta qui,
  /// ma a ogni lettura successiva.
  Future<void> storeBioKey(Uint8List bioKey) async {
    if (!Platform.isAndroid) return;
    await _storage.write(
        key: _key, value: base64Encode(bioKey), aOptions: _options);
  }

  /// Legge la bioKey: mostra il BiometricPrompt e restituisce la chiave solo se
  /// l'autenticazione riesce.
  Future<({BiometricReadResult result, Uint8List? bioKey})>
      readBioKey() async {
    if (!Platform.isAndroid) {
      return (result: BiometricReadResult.unavailable, bioKey: null);
    }
    try {
      final value = await _storage.read(key: _key, aOptions: _options);
      if (value == null) {
        return (result: BiometricReadResult.unavailable, bioKey: null);
      }
      return (result: BiometricReadResult.success, bioKey: base64Decode(value));
    } on PlatformException {
      return (result: BiometricReadResult.canceled, bioKey: null);
    } catch (_) {
      return (result: BiometricReadResult.unavailable, bioKey: null);
    }
  }

  Future<void> deleteBioKey() async {
    if (!Platform.isAndroid) return;
    try {
      await _storage.delete(key: _key, aOptions: _options);
    } catch (_) {}
  }
}
