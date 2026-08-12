import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../crypto/models.dart';
import '../../crypto/passone_file.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import 'password_dialog.dart';

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  bool _loading = false;
  String? _error;
  String? _info;

  Future<void> _pickAndImport() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
            label: 'PassOne',
            extensions: ['passone'],
            mimeTypes: ['application/octet-stream']),
        XTypeGroup(label: 'Vault', extensions: ['json', 'csv']),
      ],
    );
    if (file == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      final content = await file.readAsString();
      final name = file.name.toLowerCase();
      final passone =
          name.endsWith('.passone') || PassoneFile.isPassoneEnvelope(content);
      final VaultData? imported;
      if (passone) {
        imported = await _importPassone(content);
      } else {
        imported = name.endsWith('.json')
            ? _importJson(content)
            : importCsv(content);
      }
      if (imported == null) return;
      final data = imported;
      final current = ref.read(sessionControllerProvider).vault ?? VaultData();
      final merged = _merge(current, data);
      await ref.read(sessionControllerProvider.notifier).saveVault(merged);
      setState(() => _info = context.l10n
          .importedCount(data.entries.length, merged.entries.length));
    } on PassoneDecryptException {
      setState(() => _error = context.l10n.importWrongPassword);
    } catch (e) {
      setState(() => _error = context.l10n.importFailed(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Returns null when the user cancels the password prompt.
  Future<VaultData?> _importPassone(String content) async {
    final l10n = context.l10n;
    final password = await promptPassword(
      context,
      title: l10n.importPassoneTitle,
      message: l10n.importPassonePrompt,
      label: l10n.importPassoneLabel,
      confirmLabel: l10n.importPassoneLabel,
      requiredError: l10n.importPassoneRequired,
      mismatchError: l10n.importWrongPassword,
    );
    if (password == null) return null;
    return PassoneFile.decrypt(content, password);
  }

  VaultData _importJson(String content) {
    final json = jsonDecode(content);
    if (json is Map<String, dynamic>) {
      return VaultData.fromJson(json);
    }
    if (json is List) {
      return VaultData(
        entries: json
            .map((e) => VaultEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    }
    throw const FormatException('Unrecognized JSON format');
  }

  VaultData _merge(VaultData current, VaultData imported) {
    final byId = <String, VaultEntry>{};
    for (final e in current.entries) {
      byId[e.id] = e;
    }
    for (final e in imported.entries) {
      final existing = byId[e.id];
      if (existing == null || e.updatedAt.isAfter(existing.updatedAt)) {
        byId[e.id] = e;
      }
    }
    return VaultData(entries: byId.values.toList());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.importTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.l10n.importIntro,
                  textAlign: TextAlign.center,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  SelectableText(_error!,
                      style: TextStyle(color: theme.colorScheme.error),
                      textAlign: TextAlign.center),
                ],
                if (_info != null) ...[
                  const SizedBox(height: 16),
                  Text(_info!, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _loading ? null : _pickAndImport,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_open),
                  label: Text(context.l10n.chooseFile),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Parses a CSV string into rows of fields (handles quoted fields, escaped
/// quotes and CRLF line endings).
List<List<String>> parseCsv(String content) {
  final rows = <List<String>>[];
  var cur = <String>[];
  var field = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < content.length; i++) {
    final c = content[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < content.length && content[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      inQuotes = true;
    } else if (c == ',') {
      cur.add(field.toString());
      field = StringBuffer();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < content.length && content[i + 1] == '\n') i++;
      cur.add(field.toString());
      field = StringBuffer();
      if (cur.any((f) => f.isNotEmpty)) rows.add(cur);
      cur = [];
    } else {
      field.write(c);
    }
  }
  cur.add(field.toString());
  if (cur.any((f) => f.isNotEmpty)) rows.add(cur);
  return rows;
}

/// Imports a CSV file into a [VaultData].
///
/// Supports plain exports (`name,url,username,password,notes`), Bitwarden
/// exports (`name,notes,...,login_uri,login_username,login_password,
/// login_totp`) and Firefox exports (`url,username,password,...`, which has
/// no `name` column, so the entry name is derived from the URL).
VaultData importCsv(String content) {
  final rows = parseCsv(content);
  if (rows.isEmpty) return VaultData();
  final headers = rows.first;
  final entries = <VaultEntry>[];
  for (final row in rows.skip(1)) {
    if (row.length < headers.length) continue;
    final m = <String, String>{};
    for (var i = 0; i < headers.length; i++) {
      m[headers[i].trim().toLowerCase()] = row[i];
    }
    final totp = (m['login_totp'] ?? m['totp'] ?? '').trim();
    final url = m['url'] ?? m['login_uri'] ?? '';
    final name = m['name'] ?? '';
    entries.add(VaultEntry.create(
      name: name.isNotEmpty ? name : nameFromUrl(url),
      url: url,
      username: m['username'] ?? m['login_username'] ?? '',
      password: m['password'] ?? m['login_password'] ?? '',
      notes: m['notes'] ?? '',
      totpSecret: totp.isEmpty ? null : totp,
    ));
  }
  return VaultData(entries: entries);
}

/// Derives a readable entry name from a URL host, e.g.
/// `https://github.com` -> `GitHub`. Returns an empty string for empty or
/// invalid URLs.
String nameFromUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return '';
  var host = Uri.tryParse(trimmed)?.host ?? '';
  if (host.isEmpty && trimmed.contains('.')) {
    final withoutScheme =
        trimmed.replaceFirst(RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://'), '');
    host = withoutScheme.split('/').first;
  }
  if (host.startsWith('www.')) host = host.substring(4);
  final label = host.split('.').first;
  if (label.isEmpty) return host;
  return label[0].toUpperCase() + label.substring(1);
}
