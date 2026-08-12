import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

/// Saves [content] asking the user where to put it.
///
/// On Android the stock `file_selector` does not implement `getSaveLocation`
/// (it throws `UnimplementedError`), so we open the system "Save as" dialog
/// (ACTION_CREATE_DOCUMENT) through a small native channel instead. On desktop
/// platforms the regular file_selector save dialog is used.
///
/// [extension] is the file extension without the dot (e.g. `passone`); on
/// Android it is appended to the file name when missing, so the exported file
/// always keeps a proper extension.
///
/// Returns the display path of the saved file, or null if the user cancelled.
Future<String?> saveFileWithDialog({
  required String suggestedName,
  required String mimeType,
  required String content,
  String? extension,
}) async {
  if (Platform.isAndroid) {
    try {
      return await _saveAndroid(
        suggestedName: suggestedName,
        mimeType: mimeType,
        content: content,
        extension: extension,
      );
    } on PlatformException {
      // Native channel unavailable: fall back to the plugin below.
    }
  }
  final destination = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: [
      XTypeGroup(label: 'File', mimeTypes: [mimeType]),
    ],
  );
  if (destination == null) return null;
  final file = File(destination.path);
  await file.writeAsString(content);
  return file.path;
}

const _channel = MethodChannel('passone/save_file');

Future<String?> _saveAndroid({
  required String suggestedName,
  required String mimeType,
  required String content,
  String? extension,
}) async {
  return _channel.invokeMethod<String>('saveFile', {
    'suggestedName': suggestedName,
    'mimeType': mimeType,
    'extension': extension,
    'bytes': utf8.encode(content),
  });
}
