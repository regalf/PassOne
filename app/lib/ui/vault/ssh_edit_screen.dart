import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../crypto/models.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';

class SshEditScreen extends ConsumerStatefulWidget {
  final VaultEntry? entry;
  final String? initialFolderId;

  const SshEditScreen({super.key, this.entry, this.initialFolderId});

  @override
  ConsumerState<SshEditScreen> createState() => _SshEditScreenState();
}

class _SshEditScreenState extends ConsumerState<SshEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _username;
  late final TextEditingController _privateKey;
  late final TextEditingController _publicKey;
  late final TextEditingController _passphrase;
  late String _folderId;
  bool _obscurePassphrase = true;

  bool get _isNew => widget.entry == null;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _name = TextEditingController(text: e?.name ?? '');
    _host = TextEditingController(text: e?.url ?? '');
    _username = TextEditingController(text: e?.username ?? '');
    _privateKey = TextEditingController(text: e?.privateKey ?? '');
    _publicKey = TextEditingController(text: e?.publicKey ?? '');
    _passphrase = TextEditingController(text: e?.passphrase ?? '');
    _folderId = e?.folderId ?? widget.initialFolderId ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _username.dispose();
    _privateKey.dispose();
    _publicKey.dispose();
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _importFile(TextEditingController target) async {
    final file = await openFile(
      acceptedTypeGroups: const [XTypeGroup(label: 'SSH keys')],
    );
    if (file == null || !mounted) return;
    try {
      final content = await file.readAsString();
      if (!mounted) return;
      setState(() => target.text = content.trim());
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.keyImported(file.name))));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.sshImportFailed)));
      }
    }
  }

  void _copy(TextEditingController c) {
    Clipboard.setData(ClipboardData(text: c.text));
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.enterName)));
      return;
    }
    final folderId = _folderId.isEmpty ? null : _folderId;
    final entry = widget.entry?.copyWith(
          name: name,
          url: _host.text.trim(),
          username: _username.text.trim(),
          privateKey: () => _privateKey.text.trim(),
          publicKey: () => _publicKey.text.trim(),
          passphrase: () => _passphrase.text,
          folderId: () => folderId,
        ) ??
        VaultEntry.create(
          name: name,
          url: _host.text.trim(),
          username: _username.text.trim(),
          privateKey: _privateKey.text.trim(),
          publicKey: _publicKey.text.trim(),
          passphrase: _passphrase.text,
          folderId: folderId,
        );
    Navigator.of(context).pop(entry);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title:
            Text(_isNew ? l10n.newSshTitle : l10n.editSshTitle),
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
            TextField(
              controller: _name,
              autofocus: _isNew,
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
              controller: _host,
              decoration: InputDecoration(
                labelText: l10n.host,
                hintText: 'github.com',
                prefixIcon: const Icon(Icons.dns_outlined),
              ),
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _username,
              decoration: InputDecoration(
                labelText: l10n.username,
                prefixIcon: const Icon(Icons.person_outline),
              ),
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: 16),
            _keyField(
              controller: _privateKey,
              label: l10n.privateKey,
              maxLines: 7,
              onImport: () => _importFile(_privateKey),
            ),
            const SizedBox(height: 12),
            _keyField(
              controller: _publicKey,
              label: l10n.publicKey,
              maxLines: 3,
              onImport: () => _importFile(_publicKey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passphrase,
              obscureText: _obscurePassphrase,
              decoration: InputDecoration(
                labelText: l10n.passphrase,
                prefixIcon: const Icon(Icons.key_outlined),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassphrase
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () =>
                      setState(() => _obscurePassphrase = !_obscurePassphrase),
                ),
              ),
            ),
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

  Widget _keyField({
    required TextEditingController controller,
    required String label,
    required int maxLines,
    required VoidCallback onImport,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: TextInputType.multiline,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: InputDecoration(
            labelText: label,
            alignLabelWithHint: true,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.copy),
              tooltip: context.l10n.copy,
              onPressed: () => _copy(controller),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.upload_file, size: 18),
            label: Text(context.l10n.importFromFile),
          ),
        ),
      ],
    );
  }
}
