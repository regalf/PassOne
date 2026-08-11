import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../crypto/models.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import 'import_screen.dart';

/// Esporta il vault in formato PassOne (JSON) o CSV.
Future<void> exportVault(BuildContext context, VaultData vault) async {
  final l10n = context.l10n;
  final format = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.l10n.exportTitle),
      content: Text(ctx.l10n.exportWarning),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop('json'),
            child: Text(ctx.l10n.jsonFull)),
        TextButton(
            onPressed: () => Navigator.of(ctx).pop('csv'),
            child: const Text('CSV')),
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(), child: Text(ctx.l10n.cancel)),
      ],
    ),
  );
  if (format == null || !context.mounted) return;

  final ext = format == 'json' ? 'json' : 'csv';
  final destination = await getSaveLocation(
    suggestedName: 'passone-export-$ext',
    acceptedTypeGroups: [
      XTypeGroup(label: ext.toUpperCase(), extensions: [ext]),
    ],
  );
  if (destination == null) return;

  final String content = format == 'json'
      ? const JsonEncoder.withIndent('  ').convert(vault.toJson())
      : vaultToCsv(vault);
  final file = File(destination.path);
  await file.writeAsString(content);
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.exportSaved(file.path))));
  }
}

/// Converte il vault in CSV (name,url,username,password,notes).
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
