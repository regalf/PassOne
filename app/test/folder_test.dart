import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:passone_app/api/client.dart';
import 'package:passone_app/crypto/models.dart';
import 'package:passone_app/crypto/passone_file.dart';
import 'package:passone_app/state/session.dart';
import 'package:passone_app/state/settings.dart';
import 'package:passone_app/ui/settings/export.dart';
import 'package:passone_app/ui/settings/import_screen.dart';

/// Session controller that keeps the vault in memory only (no network).
class _MemoryController extends SessionController {
  _MemoryController() : super(SettingsRepository());
  @override
  Future<void> saveVault(VaultData vault) async {
    state = state.copyWith(vault: vault);
  }
  @override
  Future<void> checkServerReachability(String url) async {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('v2 vault JSON roundtrip preserves folders and folderId', () {
    final folder = VaultFolder.create(name: 'Work');
    final entry = VaultEntry.create(name: 'GitHub', folderId: folder.id);
    final vault = VaultData(entries: [entry], folders: [folder]);
    final restored = VaultData.fromJson(jsonDecode(jsonEncode(vault.toJson())));
    expect(restored.folders.length, 1);
    expect(restored.folders.first.name, 'Work');
    expect(restored.entries.first.folderId, folder.id);
  });

  test('v1 vault JSON without folders still parses (back-compat)', () {
    const json = '{"version":1,"entries":[{"id":"a","name":"GitHub","url":"",'
        '"username":"u","password":"p","notes":"","totpSecret":null,'
        '"privateKey":null,"publicKey":null,"passphrase":null,'
        '"createdAt":"2026-01-01T00:00:00.000Z",'
        '"updatedAt":"2026-01-01T00:00:00.000Z"}]}';
    final vault = VaultData.fromJson(jsonDecode(json));
    expect(vault.entries.length, 1);
    expect(vault.folders, isEmpty);
    expect(vault.entries.first.folderId, isNull);
  });

  test('export CSV includes the folder column', () {
    final folder = VaultFolder.create(name: 'Work');
    final entry = VaultEntry.create(
        name: 'GitHub', username: 'alice', password: 'secret',
        folderId: folder.id);
    final csv = vaultToCsv(VaultData(entries: [entry], folders: [folder]));
    expect(csv, startsWith('folder,name,url,username,password,notes\n'));
    expect(csv, contains('Work,GitHub,,alice,secret,'));
  });

  test('plain CSV import creates folders from the folder column', () {
    const csv = 'folder,name,url,username,password,notes\n'
        'Work,GitHub,https://github.com,alice,secret,\n'
        'Work,Mail,https://mail.example.com,bob,hunter2,\n'
        'Personal,Home,,carl,pw,\n';
    final vault = importCsv(csv);
    expect(vault.folders.length, 2);
    expect(vault.entries.length, 3);
    final work = vault.folders.firstWhere((f) => f.name == 'Work');
    expect(vault.entries.where((e) => e.folderId == work.id).length, 2);
    final personal = vault.folders.firstWhere((f) => f.name == 'Personal');
    expect(
        vault.entries.firstWhere((e) => e.name == 'Home').folderId,
        personal.id);
  });

  test('entries without a folder keep folderId null on CSV import', () {
    const csv = 'folder,name,url,username,password,notes\n'
        ',GitHub,https://github.com,alice,secret,\n';
    final vault = importCsv(csv);
    expect(vault.folders, isEmpty);
    expect(vault.entries.first.folderId, isNull);
  });

  test('Bitwarden CSV import creates folders from the folder column', () {
    const csv = 'folder,favorite,type,name,notes,fields,reprompt,'
        'login_uri,login_username,login_password,login_totp\n'
        'Social,,login,GitHub,,,0,https://github.com,alice,secret,\n';
    final vault = importBitwardenCsv(csv);
    expect(vault.folders.length, 1);
    expect(vault.folders.first.name, 'Social');
    expect(vault.entries.first.folderId, vault.folders.first.id);
  });

  test('.passone roundtrip preserves folders', () async {
    final folder = VaultFolder.create(name: 'Work');
    final entry = VaultEntry.create(name: 'GitHub', folderId: folder.id);
    final vault = VaultData(entries: [entry], folders: [folder]);
    final envelope = await PassoneFile.encrypt(vault, 'pw');
    final restored = await PassoneFile.decrypt(envelope, 'pw');
    expect(restored.folders.length, 1);
    expect(restored.folders.first.name, 'Work');
    expect(restored.entries.first.folderId, folder.id);
  });

  test('folder CRUD updates the vault state', () async {
    final c = _MemoryController();
    // Let the async _init() finish before overwriting the state.
    await pumpEventQueue();
    final entry = VaultEntry.create(name: 'GitHub');
    c.state = SessionState(
      status: AuthStatus.unlocked,
      user: UserInfo(
          id: 1,
          username: 'u',
          status: 'active',
          vaultRevision: 1,
          recoveryEnabled: false,
          kdfAlgorithm: 'argon2id'),
      vault: VaultData(entries: [entry]),
    );

    final folder = await c.addFolder('Work');
    expect(folder.id, isNotEmpty);
    expect(c.state.vault!.folders, hasLength(1));

    await c.renameFolder(folder.id, 'Jobs');
    expect(c.state.vault!.folders.single.name, 'Jobs');

    await c.moveEntryToFolder(entry.id, folder.id);
    expect(c.state.vault!.entries.single.folderId, folder.id);

    await c.deleteFolder(folder.id);
    expect(c.state.vault!.folders, isEmpty);
    expect(c.state.vault!.entries.single.folderId, isNull,
        reason: 'deleting a folder removes it from its entries');
  });
}
