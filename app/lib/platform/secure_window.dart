import 'dart:io';

import 'package:flutter/services.dart';

/// Prevents screenshots/recordings while sensitive content is on screen by
/// toggling Android's FLAG_SECURE on the activity window. No-op on other
/// platforms (and in tests where the platform channel is missing).
class SecureWindow {
  static const MethodChannel _channel = MethodChannel('passone/secure_window');

  static Future<void> setSecure(bool secure) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setSecure', {'secure': secure});
    } catch (_) {
      // Channel not registered (tests/unsupported builds): ignore.
    }
  }

  /// Runs [action] with FLAG_SECURE active and guarantees it is restored even
  /// if [action] throws.
  static Future<T> guarded<T>(Future<T> Function() action) async {
    await setSecure(true);
    try {
      return await action();
    } finally {
      await setSecure(false);
    }
  }
}
