import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../crypto/models.dart';
import '../../l10n/l10n.dart';
import '../vault/generator_dialog.dart';

class EntryEditScreen extends StatefulWidget {
  final VaultEntry? entry;

  const EntryEditScreen({super.key, this.entry});

  @override
  State<EntryEditScreen> createState() => _EntryEditScreenState();
}

class _EntryEditScreenState extends State<EntryEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _notes;
  bool _obscure = true;

  bool get _isNew => widget.entry == null;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _name = TextEditingController(text: e?.name ?? '');
    _url = TextEditingController(text: e?.url ?? '');
    _username = TextEditingController(text: e?.username ?? '');
    _password = TextEditingController(text: e?.password ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _username.dispose();
    _password.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _generate() {
    showDialog(
      context: context,
      builder: (_) => GeneratorDialog(
        onGenerated: (p) => setState(() {
          _password.text = p;
          _obscure = false;
        }),
      ),
    );
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.enterName)));
      return;
    }
    final entry = widget.entry?.copyWith(
          name: name,
          url: _url.text.trim(),
          username: _username.text.trim(),
          password: _password.text,
          notes: _notes.text,
        ) ??
        VaultEntry.create(
          name: name,
          url: _url.text.trim(),
          username: _username.text.trim(),
          password: _password.text,
          notes: _notes.text,
        );
    Navigator.of(context).pop(entry);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? context.l10n.newEntryTitle : context.l10n.editEntryTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: context.l10n.save,
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
                labelText: context.l10n.name,
                prefixIcon: const Icon(Icons.label_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              decoration: InputDecoration(
                labelText: context.l10n.url,
                hintText: 'https://example.com',
                prefixIcon: const Icon(Icons.link),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _username,
              decoration: InputDecoration(
                labelText: context.l10n.usernameEmail,
                prefixIcon: const Icon(Icons.person_outline),
              ),
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: context.l10n.password,
                prefixIcon: const Icon(Icons.key_outlined),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.auto_awesome),
                      tooltip: context.l10n.generate,
                      onPressed: _generate,
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy),
                      tooltip: context.l10n.copy,
                      onPressed: () => Clipboard.setData(
                          ClipboardData(text: _password.text)),
                    ),
                    IconButton(
                      icon: Icon(_obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: context.l10n.notes,
                prefixIcon: const Icon(Icons.notes),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: Text(context.l10n.save),
            ),
          ],
        ),
      ),
    );
  }
}
