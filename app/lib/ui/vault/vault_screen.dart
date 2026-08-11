import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../crypto/models.dart';
import '../../crypto/totp.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../settings/settings_screen.dart';
import 'entry_edit_screen.dart';
import 'qr_scanner_screen.dart';

class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen>
    with SingleTickerProviderStateMixin {
  String _query = '';
  String _error = '';
  int _tab = 0; // 0 = Password, 1 = TOTP
  late final TabController _tabController = TabController(length: 2, vsync: this)
    ..addListener(() {
      final t = _tabController.index;
      if (t != _tab) {
        setState(() => _tab = t);
        if (t == 1) _refreshTotp();
      }
    });
  Timer? _ticker;
  Map<String, String> _codes = {};
  int _secondsLeft = 30;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _refreshTotp());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  VaultData get _vault => ref.watch(sessionControllerProvider).vault ?? VaultData();

  bool _matchesQuery(VaultEntry e) {
    final q = _query.toLowerCase();
    return q.isEmpty ||
        e.name.toLowerCase().contains(q) ||
        e.username.toLowerCase().contains(q) ||
        e.url.toLowerCase().contains(q);
  }

  List<VaultEntry> get _passwordEntries =>
      _vault.entries.where((e) => !e.isTotp && _matchesQuery(e)).toList();

  List<VaultEntry> get _totpEntries =>
      _vault.entries.where((e) => e.isTotp && _matchesQuery(e)).toList();

  List<VaultEntry> get _allTotpEntries =>
      (ref.read(sessionControllerProvider).vault ?? VaultData())
          .entries
          .where((e) => e.isTotp)
          .toList();

  Future<void> _refreshTotp() async {
    if (!mounted || _tab != 1) return;
    final entries = _allTotpEntries;
    final now = DateTime.now();
    final left = totpSecondsLeft(now);
    if (entries.isEmpty) {
      if (_codes.isNotEmpty || _secondsLeft != left) {
        setState(() {
          _codes = {};
          _secondsLeft = left;
        });
      }
      return;
    }
    final codes = <String, String>{};
    for (final e in entries) {
      final s = e.totpSecret;
      if (s == null) continue;
      codes[e.id] = await generateTotp(s, time: now);
    }
    if (!mounted) return;
    setState(() {
      _codes = codes;
      _secondsLeft = left;
    });
  }

  Future<void> _scanQr() async {
    ref.read(sessionControllerProvider.notifier).touch();
    final data = await Navigator.of(context).push<TotpUriData>(
        MaterialPageRoute(builder: (_) => const QrScannerScreen()));
    if (data == null || !mounted) return;
    final name = data.label.isNotEmpty ? data.label : 'TOTP';
    final entry = VaultEntry.create(
      name: name,
      notes: context.l10n.totpNotes,
      totpSecret: data.secret,
    );
    await _save([..._vault.entries, entry]);
    _refreshTotp();
  }

  void _copyTotp(VaultEntry e) async {
    ref.read(sessionControllerProvider.notifier).touch();
    final code = _codes[e.id];
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.codeCopied)));
    }
  }

  Future<void> _deleteTotp(VaultEntry e) async {
    final ok = await showDialog<bool>(
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
    );
    if (ok == true) {
      await _save(_vault.entries.where((x) => x.id != e.id).toList());
      _refreshTotp();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vault = _vault;
    final entries = _tab == 0 ? _passwordEntries : _totpEntries;

    return Scaffold(
      appBar: AppBar(
        title: Text(_userName().isNotEmpty ? _userName() : context.l10n.appTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: context.l10n.lockTooltip,
            onPressed: () => ref.read(sessionControllerProvider.notifier).lock(),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: context.l10n.settingsTooltip,
            onPressed: () {
              final notifier = ref.read(sessionControllerProvider.notifier);
              notifier.touch();
              Navigator.of(context)
                  .push(MaterialPageRoute(
                      builder: (_) => const SettingsScreen()))
                  .then((_) => notifier.touch());
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(112),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: context.l10n.searchVault,
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              TabBar(
                controller: _tabController,
                tabs: [
                  Tab(icon: const Icon(Icons.key_outlined), text: context.l10n.tabPasswords),
                  Tab(icon: const Icon(Icons.pin_outlined), text: context.l10n.tabTotp),
                ],
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: () async {
                ref.read(sessionControllerProvider.notifier).touch();
                final entry = await Navigator.of(context).push<VaultEntry>(
                    MaterialPageRoute(builder: (_) => const EntryEditScreen()));
                if (entry != null) {
                  await _save([entry, ...vault.entries]);
                }
              },
              icon: const Icon(Icons.add),
              label: Text(context.l10n.newFab),
            )
          : FloatingActionButton.extended(
              onPressed: _scanQr,
              icon: const Icon(Icons.photo_camera),
              label: Text(context.l10n.addFab),
            ),
      body: _error.isNotEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SelectableText(_error,
                    style: TextStyle(color: theme.colorScheme.error),
                    textAlign: TextAlign.center),
              ),
            )
          : entries.isEmpty
              ? Center(
                  child: Text(
                    _query.isEmpty
                        ? (_tab == 0
                            ? context.l10n.emptyVault
                            : context.l10n.emptyTotp)
                        : context.l10n.noResults(_query),
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) => _tab == 0
                      ? _passwordTile(entries[i], theme)
                      : _totpTile(entries[i], theme),
                ),
    );
  }

  String _userName() =>
      ref.watch(sessionControllerProvider).user?.username ?? '';

  Widget _passwordTile(VaultEntry e, ThemeData theme) {
    return ListTile(
      leading: CircleAvatar(child: Text(_initial(e.name))),
      title: Text(e.name),
      subtitle: Text(
        [e.username, e.url].where((s) => s.isNotEmpty).join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () async {
        ref.read(sessionControllerProvider.notifier).touch();
        final edited = await Navigator.of(context).push<VaultEntry>(
            MaterialPageRoute(
                builder: (_) => EntryEditScreen(entry: e)));
        if (edited != null) {
          await _save(_vault.entries
              .map((x) => x.id == edited.id ? edited : x)
              .toList());
        }
      },
      trailing: PopupMenuButton<String>(
        onSelected: (v) => _action(e, v),
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
        onSelected: (v) {
          if (v == 'copy') _copyTotp(e);
          if (v == 'delete') _deleteTotp(e);
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'copy', child: Text(context.l10n.copyCode)),
          PopupMenuItem(value: 'delete', child: Text(context.l10n.delete)),
        ],
      ),
    );
  }

  String _initial(String name) =>
      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

  void _action(VaultEntry e, String action) async {
    ref.read(sessionControllerProvider.notifier).touch();
    final vault = ref.read(sessionControllerProvider).vault;
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
        final ok = await showDialog<bool>(
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
        );
        if (ok == true && vault != null) {
          await _save(vault.entries.where((x) => x.id != e.id).toList());
        }
    }
  }

  Future<void> _save(List<VaultEntry> entries) async {
    setState(() => _error = '');
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .saveVault(VaultData(entries: entries));
    } catch (e) {
      setState(() => _error = context.l10n.syncError(e));
    }
  }
}
