import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../crypto/models.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';

/// Detail/edit screen for a WebAuthn passkey. The key material is read-only:
/// only the display labels (name, username, folder) can be changed.
class PasskeyEditScreen extends ConsumerStatefulWidget {
  final VaultEntry entry;

  const PasskeyEditScreen({super.key, required this.entry});

  @override
  ConsumerState<PasskeyEditScreen> createState() => _PasskeyEditScreenState();
}

class _PasskeyEditScreenState extends ConsumerState<PasskeyEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _username;
  late final TextEditingController _privateKey;
  late final TextEditingController _publicKey;
  late String _folderId;
  bool _obscurePrivateKey = true;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _name = TextEditingController(text: e.name);
    _username = TextEditingController(text: e.username);
    _privateKey = TextEditingController(text: e.passkeyPrivateKey ?? '');
    _publicKey = TextEditingController(text: e.passkeyPublicKey ?? '');
    _folderId = e.folderId ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _privateKey.dispose();
    _publicKey.dispose();
    super.dispose();
  }

  void _copy(String value, String snack) {
    Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(snack)));
    }
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.enterName)));
      return;
    }
    final folderId = _folderId.isEmpty ? null : _folderId;
    Navigator.of(context).pop(widget.entry.copyWith(
          name: name,
          username: _username.text.trim(),
          folderId: () => folderId,
        ));
  }

  /// Base64url (or base64) -> uppercase hex bytes, 8 per line.
  /// The stored values are unpadded base64url, so pad to a multiple of 4
  /// before decoding.
  static String _hex(String b64) {
    final padding = (4 - b64.length % 4) % 4;
    final bytes = base64Url.decode(b64 + ('=' * padding));
    final sb = StringBuffer();
    for (var i = 0; i < bytes.length; i++) {
      if (i > 0) sb.write(i % 8 == 0 ? '\n' : ' ');
      sb.write(bytes[i].toRadixString(16).padLeft(2, '0').toUpperCase());
    }
    return sb.toString();
  }

  String _date(DateTime d) =>
      DateFormat.yMd().add_Hm().format(d.toLocal());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final e = widget.entry;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.editPasskeyTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: l10n.save,
            onPressed: _save,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline,
                    color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.passkeyReadOnly,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              enableIMEPersonalizedLearning: false,
              controller: _name,
              autofocus: false,
              decoration: InputDecoration(
                labelText: l10n.name,
                prefixIcon: const Icon(Icons.label_outline),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _folderId,
              decoration: InputDecoration(
                labelText: l10n.folder,
                prefixIcon: const Icon(Icons.folder_outlined),
              ),
              items: [
                DropdownMenuItem(value: '', child: Text(l10n.noFolder)),
                for (final f in ref
                        .watch(sessionControllerProvider)
                        .vault
                        ?.folders ??
                    const <VaultFolder>[])
                  DropdownMenuItem(value: f.id, child: Text(f.name)),
              ],
              onChanged: (v) => setState(() => _folderId = v ?? ''),
            ),
            const SizedBox(height: 12),
            TextField(
              enableIMEPersonalizedLearning: false,
              controller: _username,
              decoration: InputDecoration(
                labelText: l10n.usernameEmail,
                prefixIcon: const Icon(Icons.person_outline),
              ),
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: 24),
            _sectionTitle(l10n.passkeyDetailsTitle),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    _infoTile(
                      label: l10n.relyingParty,
                      value: e.passkeyRpId ?? '',
                      copyText: e.passkeyRpId,
                      copiedMessage: l10n.rpIdCopied,
                    ),
                    if (e.passkeyCredentialId != null)
                      _infoTile(
                        label: l10n.credentialIdLabel,
                        value: _hex(e.passkeyCredentialId!),
                        copyText: e.passkeyCredentialId,
                        copiedMessage: l10n.credentialIdCopied,
                      ),
                    if (e.passkeyUserHandle?.isNotEmpty == true)
                      _infoTile(
                        label: l10n.userHandle,
                        value: _hex(e.passkeyUserHandle!),
                        copyText: e.passkeyUserHandle,
                        copiedMessage: l10n.userHandleCopied,
                      ),
                    _infoTile(label: l10n.algorithm, value: 'ES256 · P-256'),
                    _infoTile(
                        label: l10n.signatureCounter,
                        value: e.passkeyCounter.toString()),
                    _infoTile(label: l10n.createdLabel, value: _date(e.createdAt)),
                    _infoTile(label: l10n.updatedLabel, value: _date(e.updatedAt)),
                  ],
                ),
              ),
            ),
            if (e.passkeyPrivateKey != null) ...[
              const SizedBox(height: 16),
              _keyField(
                controller: _privateKey,
                label: l10n.privateKey,
                obscure: _obscurePrivateKey,
                onToggleObscure: () => setState(
                    () => _obscurePrivateKey = !_obscurePrivateKey),
                onCopy: () => _copy(e.passkeyPrivateKey!, l10n.privateKeyCopied),
              ),
            ],
            if (e.passkeyPublicKey != null) ...[
              const SizedBox(height: 12),
              _keyField(
                controller: _publicKey,
                label: l10n.publicKey,
                onCopy: () => _copy(e.passkeyPublicKey!, l10n.publicKeyCopied),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      child: Text(title.toUpperCase(),
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.primary)),
    );
  }

  Widget _infoTile({
    required String label,
    required String value,
    String? copyText,
    String? copiedMessage,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                SelectableText(
                  value.isEmpty ? '—' : value,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontFamily: 'monospace', fontSize: 13),
                ),
              ],
            ),
          ),
          if (copyText != null && copyText.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: context.l10n.copy,
              onPressed: () => _copy(copyText, copiedMessage ?? ''),
            ),
        ],
      ),
    );
  }

  Widget _keyField({
    required TextEditingController controller,
    required String label,
    bool obscure = false,
    VoidCallback? onToggleObscure,
    required VoidCallback onCopy,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          enableIMEPersonalizedLearning: false,
          controller: controller,
          readOnly: true,
          obscureText: obscure,
          maxLines: obscure ? 1 : 5,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: InputDecoration(
            labelText: label,
            alignLabelWithHint: true,
            border: const OutlineInputBorder(),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onToggleObscure != null)
                  IconButton(
                    icon: Icon(obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: onToggleObscure,
                  ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: context.l10n.copy,
                  onPressed: onCopy,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
