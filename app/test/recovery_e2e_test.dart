import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:passone_app/api/client.dart';
import 'package:passone_app/crypto/kdf.dart';
import 'package:passone_app/crypto/models.dart';
import 'package:passone_app/crypto/vault_crypto.dart';
import 'package:passone_app/state/settings.dart';

void main() {
  const baseUrl = 'http://127.0.0.1:18334';

  setUpAll(() async {
    // The integration server may not be running: in that case skip.
    final ok = await _serverUp(baseUrl);
    if (!ok) {
      markTestSkipped(
          'integration server not reachable on $baseUrl (start: passone serve --config test/integration.yaml)');
    }
  });

  test('register with recovery + recover + login end-to-end', () async {
    final client = PassOneClient(baseUrl: baseUrl);
    final username = 'rec_e2e_${DateTime.now().millisecondsSinceEpoch}';
    const password = 'test-password-123';

    // ---- register (like SessionController.register) ----
    final salt = VaultCrypto.randomBytes(16);
    final kdf = KdfParams.pbkdf2(iterations: 100000);
    final kek = await Kdf().derive(password, salt, kdf);
    final authHashB64 = VaultCrypto.bytesToB64(await sha256Bytes(kek));
    final vaultKey = VaultCrypto.generateVaultKey();

    final recoveryKey = VaultCrypto.bytesToB64(VaultCrypto.randomBytes(32));
    final recBytes = VaultCrypto.b64ToBytes(recoveryKey);
    final wrappedRecov = await VaultCrypto.wrapKey(recBytes, vaultKey);
    final recoveryHashB64 =
        VaultCrypto.bytesToB64(await sha256Bytes(recBytes));

    final wrapped = await VaultCrypto.wrapKey(kek, vaultKey);
    final vaultData = VaultData(
      entries: [
        VaultEntry.create(
          name: 'test',
          username: 'u',
          password: 'p',
          url: 'https://x',
        ),
      ],
    );
    final (blob, nonce) =
        await VaultCrypto.encrypt(vaultKey, VaultCrypto.encodeJson(vaultData.toJson()));

    // Cryptographic invariants of the current implementation
    expect(wrapped.length, 60, reason: 'wrappedKey 32B -> 60 bytes');
    expect(wrappedRecov.length, 60, reason: 'wrappedRecov 32B -> 60 bytes');

    final session = await client.setup(
      username: username,
      authHashB64: authHashB64,
      saltB64: VaultCrypto.bytesToB64(salt),
      kdf: kdf.toJson(),
      wrappedKeyB64: VaultCrypto.bytesToB64(wrapped),
      wrappedRecoveryB64: VaultCrypto.bytesToB64(wrappedRecov),
      recoveryHashB64: recoveryHashB64,
      blobB64: VaultCrypto.bytesToB64(blob),
      nonceB64: VaultCrypto.bytesToB64(nonce),
      deviceName: 'test',
    );
    expect(session.user.recoveryEnabled, isTrue);

    // ---- recover (like SessionController.recover) ----
    final payload = await client.recoverPayload(
      username: username,
      recoveryHashB64:
          VaultCrypto.bytesToB64(await sha256Bytes(recBytes)),
    );
    expect(payload.wrappedRecoveryKey, isNotNull);
    expect(payload.wrappedRecoveryKey!.length, 60);

    final vaultKey2 =
        await VaultCrypto.unwrapKey(recBytes, payload.wrappedRecoveryKey!);
    expect(bytesEqual(vaultKey2, vaultKey), isTrue,
        reason: 'unwrap with the recovery key must return the vault key');

    final decrypted = VaultData.fromJson(VaultCrypto.decodeJson(
        await VaultCrypto.decrypt(vaultKey2, payload.blob, payload.nonce)));
    expect(decrypted.entries.single.name, 'test');

    // ---- login + unlock (like SessionController.login) ----
    final loginSession = await client.login(
      username: username,
      authHashB64: authHashB64,
      deviceName: 'test2',
    );
    final remote = await client.vaultGet(loginSession.token);
    final vaultKey3 = await VaultCrypto.unwrapKey(kek, remote.wrappedKey);
    expect(bytesEqual(vaultKey3, vaultKey), isTrue);
    final decrypted2 = VaultData.fromJson(VaultCrypto.decodeJson(
        await VaultCrypto.decrypt(vaultKey3, remote.blob, remote.nonce)));
    expect(decrypted2.entries.single.name, 'test');
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

bool bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
