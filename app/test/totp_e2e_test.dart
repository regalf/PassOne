import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:passone_app/api/client.dart';
import 'package:passone_app/crypto/kdf.dart';
import 'package:passone_app/crypto/models.dart';
import 'package:passone_app/crypto/totp.dart';
import 'package:passone_app/crypto/vault_crypto.dart';
import 'package:passone_app/state/settings.dart';

/// Verifies that TOTP seeds are persisted correctly in the server DB:
/// registers a user with a seed in the vault, logs in "from scratch" (new
/// session), re-downloads and decrypts the blob from the DB, and checks that
/// the seed is intact and still usable.
void main() {
  const baseUrl = 'http://127.0.0.1:18334';

  setUpAll(() async {
    final ok = await _serverUp(baseUrl);
    if (!ok) {
      markTestSkipped(
          'integration server not reachable on $baseUrl (start: passone serve --config test/integration.yaml)');
    }
  });

  test('TOTP seeds survive a DB save (register -> login)', () async {
    const secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
    final client = PassOneClient(baseUrl: baseUrl);
    final username = 'totp_e2e_${DateTime.now().millisecondsSinceEpoch}';
    const password = 'test-password-123';

    // ---- register with a vault containing a TOTP seed ----
    final salt = VaultCrypto.randomBytes(16);
    final kdf = KdfParams.pbkdf2(iterations: 100000);
    final kek = await Kdf().derive(password, salt, kdf);
    final authHashB64 = VaultCrypto.bytesToB64(await sha256Bytes(kek));
    final vaultKey = VaultCrypto.generateVaultKey();
    final wrapped = await VaultCrypto.wrapKey(kek, vaultKey);

    final vaultData = VaultData(entries: [
      VaultEntry.create(
          name: 'GitHub',
          username: 'alice',
          totpSecret: secret),
    ]);
    final (blob, nonce) = await VaultCrypto.encrypt(
        vaultKey, VaultCrypto.encodeJson(vaultData.toJson()));

    final session = await client.setup(
      username: username,
      authHashB64: authHashB64,
      saltB64: VaultCrypto.bytesToB64(salt),
      kdf: kdf.toJson(),
      wrappedKeyB64: VaultCrypto.bytesToB64(wrapped),
      wrappedRecoveryB64: null,
      recoveryHashB64: null,
      blobB64: VaultCrypto.bytesToB64(blob),
      nonceB64: VaultCrypto.bytesToB64(nonce),
      deviceName: 'test',
    );
    expect(session.token, isNotEmpty);

    // ---- login "from scratch": the vault is read from the DB ----
    final loginSession = await client.login(
      username: username,
      authHashB64: authHashB64,
      deviceName: 'test2',
    );
    final remote = await client.vaultGet(loginSession.token);
    final vaultKey2 = await VaultCrypto.unwrapKey(kek, remote.wrappedKey);
    final decrypted = VaultData.fromJson(VaultCrypto.decodeJson(
        await VaultCrypto.decrypt(vaultKey2, remote.blob, remote.nonce)));

    final entry = decrypted.entries.single;
    expect(entry.name, 'GitHub');
    expect(entry.isTotp, isTrue,
        reason: 'the seed must have been saved in the DB');
    expect(entry.totpSecret, secret,
        reason: 'the Base32 seed must come back byte-identical from the DB');

    // The seed read back from the DB still generates the correct code for the
    // current time.
    expect(await verifyTotp(entry.totpSecret!, await generateTotp(entry.totpSecret!)),
        isTrue);
  });

  test('a vault update saves/updates TOTP seeds (PUT -> GET)', () async {
    const secret1 = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
    const secret2 = 'JBSWY3DPEHPK3PXP';
    final client = PassOneClient(baseUrl: baseUrl);
    final username = 'totp_put_${DateTime.now().millisecondsSinceEpoch}';
    const password = 'test-password-123';

    final salt = VaultCrypto.randomBytes(16);
    final kdf = KdfParams.pbkdf2(iterations: 100000);
    final kek = await Kdf().derive(password, salt, kdf);
    final authHashB64 = VaultCrypto.bytesToB64(await sha256Bytes(kek));
    final vaultKey = VaultCrypto.generateVaultKey();
    final wrapped = await VaultCrypto.wrapKey(kek, vaultKey);

    final vaultData = VaultData(entries: [
      VaultEntry.create(name: 'GitHub', totpSecret: secret1),
    ]);
    final (blob, nonce) = await VaultCrypto.encrypt(
        vaultKey, VaultCrypto.encodeJson(vaultData.toJson()));

    final session = await client.setup(
      username: username,
      authHashB64: authHashB64,
      saltB64: VaultCrypto.bytesToB64(salt),
      kdf: kdf.toJson(),
      wrappedKeyB64: VaultCrypto.bytesToB64(wrapped),
      wrappedRecoveryB64: null,
      recoveryHashB64: null,
      blobB64: VaultCrypto.bytesToB64(blob),
      nonceB64: VaultCrypto.bytesToB64(nonce),
      deviceName: 'test',
    );

    // PUT: adds a second TOTP seed and a password entry.
    final updated = VaultData(entries: [
      VaultEntry.create(name: 'GitHub', totpSecret: secret1),
      VaultEntry.create(name: 'Test', password: 'pw', username: 'u'),
      VaultEntry.create(name: 'Google', totpSecret: secret2),
    ]);
    final (blob2, nonce2) = await VaultCrypto.encrypt(
        vaultKey, VaultCrypto.encodeJson(updated.toJson()));
    final newRev = await client.vaultPut(
      session.token,
      baseRevision: session.user.vaultRevision,
      blobB64: VaultCrypto.bytesToB64(blob2),
      nonceB64: VaultCrypto.bytesToB64(nonce2),
    );
    expect(newRev, greaterThan(session.user.vaultRevision));

    // GET: reads back from the DB after the update.
    final remote = await client.vaultGet(session.token);
    final decrypted = VaultData.fromJson(VaultCrypto.decodeJson(
        await VaultCrypto.decrypt(vaultKey, remote.blob, remote.nonce)));

    final byName = {for (final e in decrypted.entries) e.name: e};
    expect(byName.keys, containsAll(['GitHub', 'Google', 'Test']));
    expect(byName['GitHub']!.totpSecret, secret1);
    expect(byName['Google']!.totpSecret, secret2);
    expect(byName['Test']!.totpSecret, isNull);
    expect(decrypted.entries.where((e) => e.isTotp).length, 2,
        reason: 'both seeds must be in the DB');
  });
}

Future<bool> _serverUp(String baseUrl) async {
  try {
    final res = await HttpClient()
        .getUrl(Uri.parse('$baseUrl/health'))
        .then((r) => r.close());
    return res.statusCode == 200;
  } catch (_) {
    return false;
  }
}
