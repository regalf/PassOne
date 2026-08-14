import 'dart:convert';

import '../crypto/models.dart';

/// How two versions of an entry clash during a merge.
enum ConflictKind {
  /// Same entry id, different content on the two sides: one of the two must
  /// be kept.
  editedEdited,

  /// Different ids with identical content (same credentials added offline on
  /// two devices): a duplicate. The user may keep both or drop one.
  duplicate,
}

/// What the user wants to keep for a conflict.
enum ConflictChoice { local, remote, both }

/// One pending conflict between the local vault and the server vault.
class VaultConflict {
  final String id;
  final ConflictKind kind;
  final VaultEntry local;
  final VaultEntry remote;

  const VaultConflict({
    required this.id,
    required this.kind,
    required this.local,
    required this.remote,
  });
}

/// A user decision for one conflict (matched by [VaultConflict.id]).
class ConflictResolution {
  final String conflictId;
  final ConflictChoice choice;

  const ConflictResolution(this.conflictId, this.choice);
}

/// Canonical content fingerprint: all fields except id and timestamps, so two
/// entries typed with the same credentials on different devices compare equal.
String entryFingerprint(VaultEntry e) {
  final json = e.toJson()
    ..remove('id')
    ..remove('createdAt')
    ..remove('updatedAt');
  return jsonEncode(json);
}

/// Detects conflicts between the local and the remote vault:
///  - [ConflictKind.editedEdited]: same id with different content;
///  - [ConflictKind.duplicate]: different id, identical content.
List<VaultConflict> findConflicts(VaultData local, VaultData remote) {
  final conflicts = <VaultConflict>[];
  final remoteById = {for (final e in remote.entries) e.id: e};

  for (final l in local.entries) {
    final r = remoteById[l.id];
    if (r != null && entryFingerprint(l) != entryFingerprint(r)) {
      conflicts.add(VaultConflict(
        id: l.id,
        kind: ConflictKind.editedEdited,
        local: l,
        remote: r,
      ));
    }
  }

  final localFp = <String, VaultEntry>{
    for (final e in local.entries) entryFingerprint(e): e,
  };
  for (final r in remote.entries) {
    final l = localFp[entryFingerprint(r)];
    if (l == null || l.id == r.id) continue;
    final id = 'dup:${l.id}:${r.id}';
    if (conflicts.any((c) => c.id == id)) continue;
    conflicts.add(VaultConflict(
      id: id,
      kind: ConflictKind.duplicate,
      local: l,
      remote: r,
    ));
  }
  return conflicts;
}

/// Applies the user's decisions to a merged vault. Unlisted conflicts are
/// left untouched (the default LWW merge result stays).
VaultData resolveConflicts(
  VaultData vault,
  List<VaultConflict> conflicts,
  List<ConflictResolution> resolutions,
) {
  final byId = {for (final c in conflicts) c.id: c};
  final entries = List<VaultEntry>.from(vault.entries);
  for (final res in resolutions) {
    final conflict = byId[res.conflictId];
    if (conflict == null) continue;
    final localIdx = entries.indexWhere((e) => e.id == conflict.local.id);
    final remoteIdx = entries.indexWhere((e) => e.id == conflict.remote.id);
    switch (res.choice) {
      case ConflictChoice.local:
        if (conflict.kind == ConflictKind.duplicate && remoteIdx >= 0) {
          entries.removeAt(remoteIdx);
        } else if (conflict.kind == ConflictKind.editedEdited &&
            localIdx >= 0) {
          entries[localIdx] = conflict.local;
        }
      case ConflictChoice.remote:
        if (conflict.kind == ConflictKind.duplicate && localIdx >= 0) {
          entries.removeAt(localIdx);
        } else if (conflict.kind == ConflictKind.editedEdited &&
            remoteIdx >= 0) {
          entries[remoteIdx] = conflict.remote;
        }
      case ConflictChoice.both:
        break;
    }
  }
  return VaultData(entries: entries, folders: vault.folders);
}
