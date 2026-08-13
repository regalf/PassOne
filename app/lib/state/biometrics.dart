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

/// Thrown when enabling biometric access is canceled by the user (no
/// fingerprint confirmation provided).
class BiometricCanceledException implements Exception {
  const BiometricCanceledException();
}

/// Biometric access: availability (local_auth) and bioKey in a dedicated
/// Android Keystore namespace. The biometric check is done explicitly with
/// local_auth on every read. flutter_secure_storage is used WITHOUT biometric
/// enforcement (its cipher would be cached for the process lifetime, so a
/// lock/unlock cycle would silently decrypt) and with a dedicated namespace so
/// legacy data written with the old biometric cipher is never migrated.
/// Only works on Android.
class BiometricService {
  static const _key = 'passone_bio_key';
  static const _options = AndroidOptions(storageNamespace: 'passone_bio');

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

  /// True if a bioKey value is already present in storage. Silent: no prompt
  /// (the storage cipher never requires authentication).
  Future<bool> hasBioKey() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _storage.read(key: _key, aOptions: _options) != null;
    } catch (_) {
      return false;
    }
  }

  /// Shows the local_auth BiometricPrompt. Returns [BiometricReadResult.success]
  /// only on a successful biometric match. The prompt always appears.
  Future<BiometricReadResult> authenticate() async {
    if (!Platform.isAndroid) return BiometricReadResult.unavailable;
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock PassOne',
        biometricOnly: true,
      );
      return ok ? BiometricReadResult.success : BiometricReadResult.canceled;
    } on PlatformException {
      return BiometricReadResult.canceled;
    } catch (_) {
      return BiometricReadResult.unavailable;
    }
  }

  /// Reads the bioKey: shows the local_auth BiometricPrompt and returns the key
  /// only if authentication succeeds. The prompt is shown on every call.
  Future<({BiometricReadResult result, Uint8List? bioKey})>
      readBioKey() async {
    if (!Platform.isAndroid) {
      return (result: BiometricReadResult.unavailable, bioKey: null);
    }
    final auth = await authenticate();
    if (auth != BiometricReadResult.success) {
      return (result: auth, bioKey: null);
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
