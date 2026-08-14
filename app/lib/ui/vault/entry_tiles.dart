import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../crypto/models.dart';
import '../../crypto/totp.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import 'entry_edit_screen.dart';
import 'passkey_edit_screen.dart';
import 'ssh_edit_screen.dart';

enum EntryListKind { password, totp, ssh, passkey, all }

/// Reusable, stateful list of vault entries with per-type tiles. Keeps its own
/// TOTP ticker so codes stay in sync wherever the list is embedded.
class EntryList extends ConsumerStatefulWidget {
  final List<VaultEntry> entries;
  final EntryListKind kind;
  final String? noResultsQuery;

  const EntryList({
    super.key,
    required this.entries,
    this.kind = EntryListKind.all,
    this.noResultsQuery,
  });

  @override
  ConsumerState<EntryList> createState() => _EntryListState();
}

class _EntryListState extends ConsumerState<EntryList> {
  Timer? _ticker;
  Map<String, String> _codes = {};
  int _secondsLeft = 30;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _refreshTotp());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshTotp();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _refreshTotp() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final now = DateTime.now();
      final codes = <String, String>{};
      for (final e in widget.entries) {
        final s = e.totpSecret;
        if (s == null) continue;
        try {
          codes[e.id] = await generateTotp(s, time: now);
        } catch (_) {
          // Invalid secret: skip this code, keep the countdown running.
        }
      }
      if (!mounted) return;
      setState(() {
        _codes = codes;
        _secondsLeft = totpSecondsLeft(now);
      });
    } finally {
      _refreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = widget.entries;
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_emptyMessage(), textAlign: TextAlign.center),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) => _tile(entries[i], theme),
    );
  }

  String _emptyMessage() {
    final l10n = context.l10n;
    final q = widget.noResultsQuery;
    if (q != null && q.isNotEmpty) return l10n.noResults(q);
    return switch (widget.kind) {
      EntryListKind.password => l10n.emptyVault,
      EntryListKind.totp => l10n.emptyTotp,
      EntryListKind.ssh => l10n.emptySsh,
      EntryListKind.passkey => l10n.emptyPasskeys,
      EntryListKind.all => l10n.emptyFolder,
    };
  }

  Widget _tile(VaultEntry e, ThemeData theme) {
    if (e.isPasskey) return _passkeyTile(e, theme);
    if (e.isTotp) return _totpTile(e, theme);
    if (e.isSsh) return _sshTile(e, theme);
    return _passwordTile(e, theme);
  }

  String _initial(String name) =>
      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

  Widget _passwordTile(VaultEntry e, ThemeData theme) {
    return ListTile(
      leading: CircleAvatar(child: Text(_initial(e.name))),
      title: Text(e.name),
      subtitle: Text(
        [e.username, e.url].where((s) => s.isNotEmpty).join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => _edit(e),
      trailing: PopupMenuButton<String>(
        onSelected: (v) => _passwordAction(e, v),
        itemBuilder: (_) => [
          PopupMenuItem(
              value: 'copy_user',
              child: Text(context.l10n.copyUsername)),
          PopupMenuItem(
              value: 'copy_pass',
              child: Text(context.l10n.copyPassword)),
          PopupMenuItem(value: 'delete', child: Text(context.l10n.delete)),
        ],
      ),
    );
  }

  Widget _totpTile(VaultEntry e, ThemeData theme) {
    final code = _codes[e.id];
    return ListTile(
      leading: CircleAvatar(child: Text(_initial(e.name))),
      title: Text(e.name),
      subtitle: Row(
        children: [
          Text(
            code ?? '··· ···',
            style: theme.textTheme.titleMedium?.copyWith(
              fontFamily: 'monospace',
              letterSpacing: 3,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 40,
            child: LinearProgressIndicator(
              value: _secondsLeft / 30,
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(context.l10n.secondsLeft(_secondsLeft),
              style: theme.textTheme.bodySmall),
        ],
      ),
      onTap: () => _copyTotp(e),
      trailing: PopupMenuButton<String>(
      onSelected: (v) async {
        if (v == 'copy') _copyTotp(e);
        if (v == 'delete' && await _confirmDelete(e)) await _remove(e.id);
      },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'copy', child: Text(context.l10n.copyCode)),
          PopupMenuItem(value: 'delete', child: Text(context.l10n.delete)),
        ],
      ),
    );
  }

  Widget _sshTile(VaultEntry e, ThemeData theme) {
    final host = e.url.isNotEmpty ? '@ ${e.url}' : '';
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.vpn_key_outlined)),
      title: Text(e.name),
      subtitle: Text(
        [e.username, host].where((s) => s.isNotEmpty).join(' '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => _editSsh(e),
      trailing: PopupMenuButton<String>(
        onSelected: (v) => _sshAction(e, v),
        itemBuilder: (_) => [
          if (e.privateKey != null)
            PopupMenuItem(
                value: 'copy_priv',
                child: Text(context.l10n.copyPrivateKey)),
          if (e.publicKey != null)
            PopupMenuItem(
                value: 'copy_pub',
                child: Text(context.l10n.copyPublicKey)),
          if (e.passphrase != null)
            PopupMenuItem(
                value: 'copy_pass',
                child: Text(context.l10n.copyPassphrase)),
          PopupMenuItem(value: 'delete', child: Text(context.l10n.delete)),
        ],
      ),
    );
  }

  Widget _passkeyTile(VaultEntry e, ThemeData theme) {
    final rp = e.passkeyRpId ?? _urlHost(e.url);
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.fingerprint)),
      title: Text(e.name),
      subtitle: Text(
        [e.username, rp ?? ''].where((s) => s.isNotEmpty).join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => _editPasskey(e),
      trailing: PopupMenuButton<String>(
        onSelected: (v) => _passkeyAction(e, v),
        itemBuilder: (_) => [
          PopupMenuItem(
              value: 'copy_user',
              child: Text(context.l10n.copyUsername)),
          if (e.passkeyCredentialId != null)
            PopupMenuItem(
                value: 'copy_cred',
                child: Text(context.l10n.copyCredentialId)),
          PopupMenuItem(value: 'delete', child: Text(context.l10n.delete)),
        ],
      ),
    );
  }

  Future<void> _passkeyAction(VaultEntry e, String action) async {
    ref.read(sessionControllerProvider.notifier).touch();
    switch (action) {
      case 'copy_user':
        await Clipboard.setData(ClipboardData(text: e.username));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.usernameCopied)));
        }
      case 'copy_cred':
        await Clipboard.setData(ClipboardData(text: e.passkeyCredentialId ?? ''));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.credentialIdCopied)));
        }
      case 'delete':
        if (await _confirmDelete(e)) await _remove(e.id);
    }
  }

  static String? _urlHost(String url) {
    final cleaned =
        url.trim().replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
    final host = cleaned.split('/').first.split(':').first.toLowerCase();
    return host.isEmpty ? null : host;
  }

  Future<void> _edit(VaultEntry e) async {
    ref.read(sessionControllerProvider.notifier).touch();
    final edited = await Navigator.of(context).push<VaultEntry>(
        MaterialPageRoute(builder: (_) => EntryEditScreen(entry: e)));
    if (edited == null || !mounted) return;
    await _replace(edited);
  }

  Future<void> _editSsh(VaultEntry e) async {
    ref.read(sessionControllerProvider.notifier).touch();
    final edited = await Navigator.of(context).push<VaultEntry>(
        MaterialPageRoute(builder: (_) => SshEditScreen(entry: e)));
    if (edited == null || !mounted) return;
    await _replace(edited);
  }

  Future<void> _editPasskey(VaultEntry e) async {
    ref.read(sessionControllerProvider.notifier).touch();
    final edited = await Navigator.of(context).push<VaultEntry>(
        MaterialPageRoute(builder: (_) => PasskeyEditScreen(entry: e)));
    if (edited == null || !mounted) return;
    await _replace(edited);
  }

  Future<void> _copyTotp(VaultEntry e) async {
    ref.read(sessionControllerProvider.notifier).touch();
    final code = _codes[e.id];
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.codeCopied)));
    }
  }

  Future<void> _passwordAction(VaultEntry e, String action) async {
    ref.read(sessionControllerProvider.notifier).touch();
    switch (action) {
      case 'copy_user':
        await Clipboard.setData(ClipboardData(text: e.username));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.usernameCopied)));
        }
      case 'copy_pass':
        await Clipboard.setData(ClipboardData(text: e.password));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.passwordCopied)));
        }
      case 'delete':
        if (await _confirmDelete(e)) await _remove(e.id);
    }
  }

  Future<void> _sshAction(VaultEntry e, String action) async {
    ref.read(sessionControllerProvider.notifier).touch();
    switch (action) {
      case 'copy_priv':
        await Clipboard.setData(ClipboardData(text: e.privateKey ?? ''));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.privateKeyCopied)));
        }
      case 'copy_pub':
        await Clipboard.setData(ClipboardData(text: e.publicKey ?? ''));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.publicKeyCopied)));
        }
      case 'copy_pass':
        await Clipboard.setData(ClipboardData(text: e.passphrase ?? ''));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.passphraseCopied)));
        }
      case 'delete':
        if (await _confirmDelete(e)) await _remove(e.id);
    }
  }

  Future<bool> _confirmDelete(VaultEntry e) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(ctx.l10n.deleteEntryTitle),
            content: Text(ctx.l10n.deleteEntryBody(e.name)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(ctx.l10n.cancel)),
              FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(ctx.l10n.delete)),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _replace(VaultEntry updated) async {
    final vault = ref.read(sessionControllerProvider).vault;
    if (vault == null) return;
    await _save(VaultData(
      entries: vault.entries
          .map((x) => x.id == updated.id ? updated : x)
          .toList(),
      folders: vault.folders,
    ));
  }

  Future<void> _remove(String id) async {
    final vault = ref.read(sessionControllerProvider).vault;
    if (vault == null) return;
    await _save(VaultData(
      entries: vault.entries.where((x) => x.id != id).toList(),
      folders: vault.folders,
    ));
  }

  Future<void> _save(VaultData vault) async {
    try {
      await ref.read(sessionControllerProvider.notifier).saveVault(vault);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.l10n.syncError(e))));
      }
    }
  }
}
