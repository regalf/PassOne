import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../crypto/models.dart';
import '../../crypto/passone_file.dart';
import '../../l10n/l10n.dart';
import '../../platform/file_save.dart';
import '../../state/providers.dart';
import 'import_screen.dart';
import 'password_dialog.dart';

/// Available export formats.
enum ExportFormat {
  passone('passone', 'passone'),
  json('json', 'json'),
  csv('csv', 'csv');

  final String ext;
  final String label;
  const ExportFormat(this.ext, this.label);
}

/// Exports the vault as PassOne (encrypted), JSON or CSV.
Future<void> exportVault(BuildContext context, VaultData vault) async {
  final l10n = context.l10n;
  final format = await _chooseFormat(context);
  if (format == null || !context.mounted) return;

  String? password;
  if (format == ExportFormat.passone) {
    password = await promptPassword(
      context,
      title: l10n.exportPasswordTitle,
      message: l10n.exportPasswordPrompt,
      label: l10n.exportPasswordLabel,
      confirmLabel: l10n.exportPasswordConfirmLabel,
      requiredError: l10n.exportPasswordRequired,
      mismatchError: l10n.passwordsDiffer,
      requireConfirmation: true,
    );
    if (password == null || !context.mounted) return;
  }

  final String content = switch (format) {
    ExportFormat.passone => await PassoneFile.encrypt(vault, password!),
    ExportFormat.json =>
      const JsonEncoder.withIndent('  ').convert(vault.toJson()),
    ExportFormat.csv => vaultToCsv(vault),
  };
  if (!context.mounted) return;

  final mimeType = switch (format) {
    ExportFormat.passone => 'application/octet-stream',
    ExportFormat.json => 'application/json',
    ExportFormat.csv => 'text/csv',
  };
  final path = await saveFileWithDialog(
    suggestedName: 'passone-export.${format.ext}',
    mimeType: mimeType,
    content: content,
    extension: format.ext,
  );
  if (path == null || !context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(l10n.exportSaved(path))));
}

Future<ExportFormat?> _chooseFormat(BuildContext context) {
  final l10n = context.l10n;
  var selected = ExportFormat.passone;
  return showDialog<ExportFormat>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(l10n.exportTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.exportWarning, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            DropdownButtonFormField<ExportFormat>(
              initialValue: selected,
              decoration: InputDecoration(labelText: l10n.exportFormatLabel),
              items: [
                for (final f in ExportFormat.values)
                  DropdownMenuItem(
                    value: f,
                    child: Text(switch (f) {
                      ExportFormat.passone => l10n.exportPassone,
                      ExportFormat.json => l10n.exportJson,
                      ExportFormat.csv => l10n.exportCsv,
                    }),
                  ),
              ],
              onChanged: (v) =>
                  setState(() => selected = v ?? ExportFormat.passone),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.cancel)),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(selected),
            child: Text(l10n.connectButton),
          ),
        ],
      ),
    ),
  );
}

/// Converts the vault to CSV (name,url,username,password,notes).
String vaultToCsv(VaultData vault) {
  final sb = StringBuffer();
  sb.writeln('name,url,username,password,notes');
  for (final e in vault.entries) {
    sb.writeln([
      _csvField(e.name),
      _csvField(e.url),
      _csvField(e.username),
      _csvField(e.password),
      _csvField(e.notes),
    ].join(','));
  }
  return sb.toString();
}

String _csvField(String v) {
  final needsQuote = v.contains(',') || v.contains('"') || v.contains('\n');
  if (!needsQuote) return v;
  return '"${v.replaceAll('"', '""')}"';
}

class ImportExportSection extends ConsumerWidget {
  const ImportExportSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return _Section(
      title: l10n.sectionData,
      children: [
        ListTile(
          leading: const Icon(Icons.upload_file),
          title: Text(l10n.exportVault),
          subtitle: Text(l10n.exportSub),
          onTap: () {
            final vault = ref.read(sessionControllerProvider).vault;
            if (vault != null) exportVault(context, vault);
          },
        ),
        ListTile(
          leading: const Icon(Icons.download),
          title: Text(l10n.importVault),
          subtitle: Text(l10n.importSub),
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ImportScreen())),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
          child: Text(title.toUpperCase(),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.primary)),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Column(children: children),
        ),
      ],
    );
  }
}
