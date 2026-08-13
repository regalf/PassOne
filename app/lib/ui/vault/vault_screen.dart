import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../crypto/models.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../settings/settings_screen.dart';
import 'entry_edit_screen.dart';
import 'entry_list_screen.dart';
import 'entry_tiles.dart';

/// Shell with the bottom navigation (Vault / Settings). The Vault tab is the
/// home hub (header, search, category cards, folders), Settings is a tab.
class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      body: _index == 0
          ? const VaultHomeScreen()
          : const SettingsScreen(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          ref.read(sessionControllerProvider.notifier).touch();
          setState(() => _index = i);
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.key_outlined),
            label: l10n.tabVault,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            label: l10n.settingsTitle,
          ),
        ],
      ),
    );
  }
}

/// Home hub: header with the user name, global search, category cards and the
/// folders section.
class VaultHomeScreen extends ConsumerStatefulWidget {
  const VaultHomeScreen({super.key});

  @override
  ConsumerState<VaultHomeScreen> createState() => _VaultHomeScreenState();
}

class _VaultHomeScreenState extends ConsumerState<VaultHomeScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  VaultData get _vault =>
      ref.watch(sessionControllerProvider).vault ?? VaultData();

  List<VaultEntry> get _searchResults {
    final q = _query.toLowerCase();
    return _vault.entries
        .where((e) =>
            e.name.toLowerCase().contains(q) ||
            e.username.toLowerCase().contains(q) ||
            e.url.toLowerCase().contains(q))
        .toList();
  }

  int _passwordCount() =>
      _vault.entries.where((e) => !e.isTotp && !e.isSsh).length;

  int _totpCount() => _vault.entries.where((e) => e.isTotp).length;

  int _sshCount() => _vault.entries.where((e) => e.isSsh).length;

  int _folderCount(VaultFolder f) =>
      _vault.entries.where((e) => e.folderId == f.id).length;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      body: Column(
        children: [
          _header(l10n),
          _autofillImportsBanner(),
          _searchBar(l10n),
          Expanded(
            child: _query.isEmpty
                ? _hub(l10n)
                : EntryList(
                    entries: _searchResults,
                    kind: EntryListKind.all,
                    noResultsQuery: _query,
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newEntry,
        icon: const Icon(Icons.add),
        label: Text(l10n.newFab),
      ),
    );
  }

  Widget _header(AppLocalizations l10n) {
    final username = ref.watch(sessionControllerProvider).user?.username ?? '';
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
        child: Row(
          children: [
            CircleAvatar(child: Text(_initial(username))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.appTitle,
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(
                              color: Theme.of(context).colorScheme.primary)),
                  Text(
                    username.isEmpty ? l10n.appTitle : username,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.lock_outline),
              tooltip: l10n.lockTooltip,
              onPressed: () =>
                  ref.read(sessionControllerProvider.notifier).lock(manual: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _autofillImportsBanner() {
    final imported = ref.watch(sessionControllerProvider).lastAutofillImports;
    if (imported <= 0) return const SizedBox.shrink();
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Material(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              Icon(Icons.autorenew,
                  size: 20, color: Theme.of(context).colorScheme.onSecondaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.autofillImported(imported),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSecondaryContainer),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: l10n.close,
                visualDensity: VisualDensity.compact,
                onPressed: () => ref
                    .read(sessionControllerProvider.notifier)
                    .clearAutofillImportNotice(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchBar(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: TextField(
        enableIMEPersonalizedLearning: false,
        controller: _search,
        onChanged: (v) => setState(() => _query = v.trim()),
        decoration: InputDecoration(
          hintText: l10n.searchVault,
          prefixIcon: const Icon(Icons.search),
          filled: true,
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _hub(AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        _sectionLabel(l10n.sectionCategories),
        _CategoryCard(
          icon: Icons.key_outlined,
          title: l10n.tabPasswords,
          count: _passwordCount(),
          countLabel: l10n.entryCount(_passwordCount()),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const EntryListScreen(
                  kind: EntryListKind.password))),
        ),
        _CategoryCard(
          icon: Icons.pin_outlined,
          title: l10n.tabTotp,
          count: _totpCount(),
          countLabel: l10n.entryCount(_totpCount()),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  const EntryListScreen(kind: EntryListKind.totp))),
        ),
        _CategoryCard(
          icon: Icons.vpn_key_outlined,
          title: l10n.tabSsh,
          count: _sshCount(),
          countLabel: l10n.entryCount(_sshCount()),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const EntryListScreen(kind: EntryListKind.ssh))),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 8, 0),
          child: Row(
            children: [
              Expanded(child: _sectionLabel(l10n.folders)),
              TextButton.icon(
                onPressed: _createFolder,
                icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                label: Text(l10n.addFolder),
              ),
            ],
          ),
        ),
        if (_vault.folders.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(l10n.noFolders,
                style: Theme.of(context).textTheme.bodyMedium),
          )
        else
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (final f in _vault.folders)
                  _folderTile(f, l10n),
              ],
            ),
          ),
      ],
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(label.toUpperCase(),
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary)),
    );
  }

  Widget _folderTile(VaultFolder f, AppLocalizations l10n) {
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.folder_outlined)),
      title: Text(f.name),
      subtitle: Text(l10n.entryCount(_folderCount(f))),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => EntryListScreen(folderId: f.id))),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'rename') _renameFolder(f);
          if (v == 'delete') _deleteFolder(f);
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'rename', child: Text(l10n.renameFolder)),
          PopupMenuItem(value: 'delete', child: Text(l10n.deleteFolder)),
        ],
      ),
    );
  }

  String _initial(String name) =>
      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

  Future<void> _newEntry() async {
    ref.read(sessionControllerProvider.notifier).touch();
    final entry = await Navigator.of(context).push<VaultEntry>(
        MaterialPageRoute(builder: (_) => const EntryEditScreen()));
    if (entry == null || !mounted) return;
    await _save(VaultData(
      entries: [..._vault.entries, entry],
      folders: _vault.folders,
    ));
  }

  Future<void> _createFolder() async {
    final name = await _folderNameDialog(null);
    if (name == null || name.isEmpty) return;
    try {
      await ref.read(sessionControllerProvider.notifier).addFolder(name);
    } catch (e) {
      _showSyncError(e);
    }
  }

  Future<void> _renameFolder(VaultFolder f) async {
    final name = await _folderNameDialog(f.name);
    if (name == null || name.isEmpty || name == f.name) return;
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .renameFolder(f.id, name);
    } catch (e) {
      _showSyncError(e);
    }
  }

  Future<void> _deleteFolder(VaultFolder f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.deleteFolderTitle),
        content: Text(ctx.l10n.deleteFolderBody(f.name)),
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
    if (ok != true) return;
    try {
      await ref.read(sessionControllerProvider.notifier).deleteFolder(f.id);
    } catch (e) {
      _showSyncError(e);
    }
  }

  Future<String?> _folderNameDialog(String? initial) {
    final controller = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(initial == null ? ctx.l10n.newFolder : ctx.l10n.renameFolder),
        content: TextField(
          enableIMEPersonalizedLearning: false,
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: ctx.l10n.folderName),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(ctx.l10n.cancel)),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: Text(ctx.l10n.save)),
        ],
      ),
    );
  }

  void _showSyncError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(context.l10n.syncError(e))));
  }

  Future<void> _save(VaultData vault) async {
    try {
      await ref.read(sessionControllerProvider.notifier).saveVault(vault);
    } catch (e) {
      _showSyncError(e);
    }
  }
}

class _CategoryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;
  final String countLabel;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.icon,
    required this.title,
    required this.count,
    required this.countLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.secondaryContainer,
          foregroundColor: theme.colorScheme.onSecondaryContainer,
          child: Icon(icon),
        ),
        title: Text(title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(countLabel),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
