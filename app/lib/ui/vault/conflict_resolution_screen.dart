import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../crypto/models.dart';
import '../../l10n/l10n.dart';
import '../../state/conflicts.dart';
import '../../state/providers.dart';

/// Dedicated screen to resolve sync conflicts between the local vault and the
/// server: per entry, two cards (device/server) with the choices to keep the
/// device version, the server version or both, a progress counter and a
/// "resolve later" escape hatch.
class ConflictResolutionScreen extends ConsumerStatefulWidget {
  const ConflictResolutionScreen({super.key});

  @override
  ConsumerState<ConflictResolutionScreen> createState() =>
      _ConflictResolutionScreenState();
}

class _ConflictResolutionScreenState
    extends ConsumerState<ConflictResolutionScreen> {
  final Map<String, ConflictChoice> _choices = {};
  final Set<String> _chosen = {};

  List<VaultConflict> get _conflicts =>
      ref.watch(sessionControllerProvider).conflicts;

  ConflictChoice _defaultFor(VaultConflict c) {
    if (c.kind == ConflictKind.duplicate) return ConflictChoice.both;
    final current = ref
        .read(sessionControllerProvider)
        .vault
        ?.entries
        .where((e) => e.id == c.id)
        .firstOrNull;
    if (current != null && entryFingerprint(current) == entryFingerprint(c.local)) {
      return ConflictChoice.local;
    }
    return ConflictChoice.remote;
  }

  ConflictChoice _choiceFor(VaultConflict c) =>
      _choices[c.id] ?? _defaultFor(c);

  void _select(VaultConflict c, ConflictChoice choice) {
    setState(() {
      _choices[c.id] = choice;
      _chosen.add(c.id);
    });
  }

  Future<void> _apply() async {
    final conflicts = _conflicts;
    if (conflicts.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final resolutions = [
      for (final c in conflicts) ConflictResolution(c.id, _choiceFor(c)),
    ];
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .applyConflictResolutions(resolutions);
    } catch (_) {
      // A real server error: keep the screen open so the user can retry.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.conflictsApplyFailed)));
      }
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.conflictsApplied)));
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final conflicts = _conflicts;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.conflictsTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Material(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.rule,
                        size: 20,
                        color: Theme.of(context)
                            .colorScheme
                            .onTertiaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.conflictsIntro(conflicts.length),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onTertiaryContainer,
                            ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.conflictsProgress(_chosen.length, conflicts.length),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              itemCount: conflicts.length,
              itemBuilder: (context, i) => _ConflictCard(
                conflict: conflicts[i],
                choice: _choiceFor(conflicts[i]),
                onChanged: (choice) => _select(conflicts[i], choice),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.conflictsResolveLater),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _apply,
                  child: Text(l10n.conflictsApply),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConflictCard extends StatelessWidget {
  final VaultConflict conflict;
  final ConflictChoice choice;
  final ValueChanged<ConflictChoice> onChanged;

  const _ConflictCard({
    required this.conflict,
    required this.choice,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final kind = conflict.kind == ConflictKind.duplicate
        ? l10n.conflictsKindDuplicate
        : l10n.conflictsKindEdited;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  conflict.kind == ConflictKind.duplicate
                      ? Icons.content_copy
                      : Icons.edit_note,
                  size: 18,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    kind,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.tertiary,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _EntryCard(
                    label: l10n.conflictsDevice,
                    entry: conflict.local,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _EntryCard(
                    label: l10n.conflictsServer,
                    entry: conflict.remote,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SegmentedButton<ConflictChoice>(
              segments: [
                ButtonSegment(
                  value: ConflictChoice.local,
                  icon: const Icon(Icons.smartphone, size: 16),
                  label: Text(l10n.conflictsUseLocal),
                ),
                ButtonSegment(
                  value: ConflictChoice.remote,
                  icon: const Icon(Icons.dns_outlined, size: 16),
                  label: Text(l10n.conflictsUseRemote),
                ),
                if (conflict.kind == ConflictKind.duplicate)
                  ButtonSegment(
                    value: ConflictChoice.both,
                    icon: const Icon(Icons.content_copy, size: 16),
                    label: Text(l10n.conflictsKeepBoth),
                  ),
              ],
              selected: {choice},
              onSelectionChanged: (s) => onChanged(s.first),
              showSelectedIcon: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  final String label;
  final VaultEntry entry;

  const _EntryCard({required this.label, required this.entry});

  String _mask(String s) =>
      s.isEmpty ? '—' : '•' * (s.length.clamp(1, 12));

  String _relativeTime(DateTime now, DateTime t) {
    final diff = now.difference(t);
    if (diff.inSeconds < 60) return '1m';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${t.day}/${t.month}/${t.year}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    String secret;
    IconData secretIcon;
    if (entry.isPasskey) {
      secret = _mask(entry.name);
      secretIcon = Icons.key_outlined;
    } else if (entry.isSsh) {
      secret = _mask(entry.name);
      secretIcon = Icons.vpn_key_outlined;
    } else if (entry.isTotp) {
      secret = _mask(entry.name);
      secretIcon = Icons.abc_outlined;
    } else {
      secret = _mask(entry.password);
      secretIcon = Icons.lock_outline;
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: text.labelSmall?.copyWith(color: scheme.primary),
          ),
          const SizedBox(height: 4),
          Text(
            entry.name.isEmpty ? '—' : entry.name,
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            entry.username.isEmpty ? '—' : entry.username,
            style: text.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (entry.url.isNotEmpty)
            Text(
              entry.url,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(secretIcon, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  secret,
                  style: text.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _relativeTime(DateTime.now(), entry.updatedAt.toLocal()),
            style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
