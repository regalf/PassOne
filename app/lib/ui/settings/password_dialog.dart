import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';

/// Asks the user for a password.
///
/// Returns the password on success, or null if cancelled. When
/// [requireConfirmation] is true a "confirm password" field is shown.
Future<String?> promptPassword(
  BuildContext context, {
  required String title,
  required String message,
  required String label,
  required String confirmLabel,
  required String requiredError,
  required String mismatchError,
  bool requireConfirmation = false,
}) {
  final l10n = context.l10n;
  final formKey = GlobalKey<FormState>();
  var first = '';

  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextFormField(
              autofocus: true,
              obscureText: true,
              decoration: InputDecoration(labelText: label),
              validator: (v) =>
                  (v == null || v.isEmpty) ? requiredError : null,
              onChanged: (v) => first = v,
            ),
            if (requireConfirmation) ...[
              const SizedBox(height: 12),
              TextFormField(
                obscureText: true,
                decoration: InputDecoration(labelText: confirmLabel),
                validator: (v) {
                  if (v == null || v.isEmpty) return requiredError;
                  if (v != first) return mismatchError;
                  return null;
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.of(ctx).pop(first);
            }
          },
          child: Text(l10n.confirm),
        ),
      ],
    ),
  );
}
