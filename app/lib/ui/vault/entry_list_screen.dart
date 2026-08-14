import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../crypto/models.dart';
import '../../crypto/totp.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import 'entry_edit_screen.dart';
import 'entry_tiles.dart';
import 'qr_scanner_screen.dart';
import 'ssh_edit_screen.dart';

/// Full-screen filtered list of vault entries, with the add button matching
/// the list kind. When [folderId] is set it shows the entries of a folder and
/// the add button offers all entry types.
class EntryListScreen extends ConsumerStatefulWidget {
  final EntryListKind kind;
  final String? folderId;

  const EntryListScreen({
    super.key,
    this.kind = EntryListKind.all,
    this.folderId,
  });

  @override
  ConsumerState<EntryListScreen> createState() => _EntryListScreenState();
}

class _EntryListScreenState extends ConsumerState<EntryListScreen> {
  EntryListKind get _kind => widget.kind;
  String? get _folderId => widget.folderId;

  List<VaultEntry> _filter(VaultData vault) {
    var list = vault.entries.where((e) => switch (_kind) {
          EntryListKind.password => !e.isTotp && !e.isSsh && !e.isPasskey,
          EntryListKind.totp => e.isTotp,
          EntryListKind.ssh => e.isSsh,
          EntryListKind.passkey => e.isPasskey,
          EntryListKind.all => true,
        }).toList();
    if (_folderId != null) {
      list = list.where((e) => e.folderId == _folderId).toList();
    }
    return list;
  }

  String _title(VaultData vault) {
    final l10n = context.l10n;
    if (_folderId != null) {
      for (final f in vault.folders) {
        if (f.id == _folderId) return f.name;
      }
    }
    return switch (_kind) {
      EntryListKind.password => l10n.tabPasswords,
      EntryListKind.totp => l10n.tabTotp,
      EntryListKind.ssh => l10n.tabSsh,
      EntryListKind.passkey => l10n.tabPasskeys,
      EntryListKind.all => l10n.appTitle,
    };
  }

  @override
  Widget build(BuildContext context) {
    final vault = ref.watch(sessionControllerProvider).vault ?? VaultData();
    return Scaffold(
      appBar: AppBar(title: Text(_title(vault))),
      floatingActionButton: _floatingActionButton(vault),
      body: EntryList(
        entries: _filter(vault),
        kind: _kind,
      ),
    );
  }

  Widget _floatingActionButton(VaultData vault) {
    // Passkeys can only be created through the system Credential Manager
    // (browser/web app), never manually from the app.
    if (_kind == EntryListKind.passkey) return const SizedBox.shrink();
    if (_kind == EntryListKind.totp) {
      return FloatingActionButton.extended(
        onPressed: () => _scanQr(vault),
        icon: const Icon(Icons.photo_camera),
        label: Text(context.l10n.addFab),
      );
    }
    if (_folderId != null) {
      return FloatingActionButton.extended(
        onPressed: () => _addToFolder(vault),
        icon: const Icon(Icons.add),
        label: Text(context.l10n.newFab),
      );
    }
    return FloatingActionButton.extended(
      onPressed: () => _add(_kind, vault, null),
      icon: const Icon(Icons.add),
      label: Text(context.l10n.newFab),
    );
  }

  Future<void> _addToFolder(VaultData vault) async {
    ref.read(sessionControllerProvider.notifier).touch();
    final kind = await showModalBottomSheet<EntryListKind>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.key_outlined),
              title: Text(ctx.l10n.tabPasswords),
              onTap: () => Navigator.of(ctx).pop(EntryListKind.password),
            ),
            ListTile(
              leading: const Icon(Icons.vpn_key_outlined),
              title: Text(ctx.l10n.tabSsh),
              onTap: () => Navigator.of(ctx).pop(EntryListKind.ssh),
            ),
            ListTile(
              leading: const Icon(Icons.pin_outlined),
              title: Text(ctx.l10n.tabTotp),
              onTap: () => Navigator.of(ctx).pop(EntryListKind.totp),
            ),
          ],
        ),
      ),
    );
    if (kind == null || !mounted) return;
    await _add(kind, vault, _folderId);
  }

  Future<void> _add(EntryListKind kind, VaultData vault, String? folderId) async {
    ref.read(sessionControllerProvider.notifier).touch();
    if (kind == EntryListKind.totp) {
      await _scanQr(vault);
      return;
    }
    final VaultEntry? entry;
    if (kind == EntryListKind.ssh) {
      entry = await Navigator.of(context).push<VaultEntry>(
          MaterialPageRoute(
              builder: (_) => SshEditScreen(initialFolderId: folderId)));
    } else {
      entry = await Navigator.of(context).push<VaultEntry>(
          MaterialPageRoute(
              builder: (_) => EntryEditScreen(initialFolderId: folderId)));
    }
    if (entry == null || !mounted) return;
    await _append(vault, entry);
  }

  Future<void> _scanQr(VaultData vault) async {
    ref.read(sessionControllerProvider.notifier).touch();
    final data = await Navigator.of(context).push<TotpUriData>(
        MaterialPageRoute(builder: (_) => const QrScannerScreen()));
    if (data == null || !mounted) return;
    final name = data.label.isNotEmpty ? data.label : 'TOTP';
    final entry = VaultEntry.create(
      name: name,
      notes: context.l10n.totpNotes,
      totpSecret: data.secret,
      folderId: _folderId,
    );
    await _append(vault, entry);
  }

  Future<void> _append(VaultData vault, VaultEntry entry) async {
    try {
      await ref.read(sessionControllerProvider.notifier).saveVault(VaultData(
            entries: [...vault.entries, entry],
            folders: vault.folders,
          ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.l10n.syncError(e))));
      }
    }
  }
}
