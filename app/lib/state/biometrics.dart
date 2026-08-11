import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Result of a read of the bioKey from the Keystore.
enum BiometricReadResult {
  /// Key read and biometrics passed.
  success,

  /// Prompt canceled or invalid fingerprint (user can retry/cancel).
  canceled,

  /// No bioKey available or key invalidated (e.g. fingerprints changed).
  unavailable,
}

/// Biometric access: availability (local_auth) and bioKey in the Android
/// Keystore protected by authentication on every read (flutter_secure_storage
/// with [AndroidOptions.biometric]). Only works on Android.
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

  /// True only on Android with strong registered biometrics (e.g. fingerprint).
  Future<bool> isAvailable() async {
    if (!Platform.isAndroid) return false;
    try {
      if (!await _auth.isDeviceSupported()) return false;
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Stores the [bioKey] in the Keystore; the biometric prompt does NOT fire here,
  /// but on every subsequent read.
  Future<void> storeBioKey(Uint8List bioKey) async {
    if (!Platform.isAndroid) return;
    await _storage.write(
        key: _key, value: base64Encode(bioKey), aOptions: _options);
  }

  /// Reads the bioKey: shows the BiometricPrompt and returns the key only if
  /// authentication succeeds.
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
