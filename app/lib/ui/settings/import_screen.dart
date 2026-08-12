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
      final VaultData imported;
      if (name.endsWith('.passone')) {
        imported = await _importPassone(content);
      } else {
        imported = name.endsWith('.json')
            ? _importJson(content)
            : _importCsv(content);
      }
      final current = ref.read(sessionControllerProvider).vault ?? VaultData();
      final merged = _merge(current, imported);
      await ref.read(sessionControllerProvider.notifier).saveVault(merged);
      setState(() => _info = context.l10n
          .importedCount(imported.entries.length, merged.entries.length));
    } on PassoneDecryptException {
      setState(() => _error = context.l10n.importWrongPassword);
    } catch (e) {
      setState(() => _error = context.l10n.importFailed(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<VaultData> _importPassone(String content) async {
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
    if (password == null) {
      throw PassoneDecryptException();
    }
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
  }  VaultData _importCsv(String content) {
    final rows = _parseCsv(content);
    if (rows.isEmpty) return VaultData();
    final headers = rows.first;
    final entries = <VaultEntry>[];
    for (final row in rows.skip(1)) {
      if (row.length < headers.length) continue;
      final m = <String, String>{};
      for (var i = 0; i < headers.length; i++) {
        m[headers[i].toLowerCase()] = row[i];
      }
      entries.add(VaultEntry.create(
        name: m['name'] ?? '',
        url: m['url'] ?? '',
        username: m['username'] ?? '',
        password: m['password'] ?? '',
        notes: m['notes'] ?? '',
      ));
    }
    return VaultData(entries: entries);
  }

  List<List<String>> _parseCsv(String content) {
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
