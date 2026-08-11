// Regressione per il bug "password mai valida": verifica setup+login+decrypt
// del vault con il VERO argon2id nativo (non testabile via flutter test).
// Uso: server attivo su <baseUrl>, poi `dart run tool/e2e_argon2.dart <baseUrl>`.
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:passone_app/api/client.dart';
import 'package:passone_app/crypto/kdf.dart';
import 'package:passone_app/crypto/vault_crypto.dart';

Future<Uint8List> sha256Bytes(List<int> data) async {
  final hash = await Sha256().hash(data);
  return Uint8List.fromList(hash.bytes);
}

Future<void> main(List<String> args) async {
  final base = args.isNotEmpty ? args[0] : 'http://127.0.0.1:8322';
  final client = PassOneClient(baseUrl: base);
  final kdf = Kdf();
  final rng = Random();

  final username = 'argon2test_${rng.nextInt(1 << 32)}';
  final password = 'PasswordCorretta-42!';

  // ==== Setup (equivalente a SessionController.register) ====
  final salt = VaultCrypto.randomBytes(16);
  final params = KdfParams.argon2id();
  final kek = await kdf.derive(password, salt, params);
  final authHash = VaultCrypto.bytesToB64(await sha256Bytes(kek));
  final vaultKey = VaultCrypto.generateVaultKey();
  final wrapped = await VaultCrypto.wrapKey(kek, vaultKey);
  final (blob, nonce) = await VaultCrypto.encrypt(
      vaultKey, VaultCrypto.encodeJson(const {'entries': []}));

  final session = await client.setup(
    username: username,
    authHashB64: authHash,
    saltB64: VaultCrypto.bytesToB64(salt),
    kdf: params.toJson(),
    wrappedKeyB64: VaultCrypto.bytesToB64(wrapped),
    blobB64: VaultCrypto.bytesToB64(blob),
    nonceB64: VaultCrypto.bytesToB64(nonce),
    deviceName: 'e2e',
  );
  print('SETUP OK: user=${session.user.username} rev=${session.user.vaultRevision}');
  await client.logout(session.token);

  // ==== Login (equivalente a SessionController.login) ====
  final pre = await client.prelogin(username);
  print('Prelogin: status=${pre.status} kdf=${pre.kdf} saltlen=${pre.salt.length}');
  final loginKek = await kdf.derive(password, pre.salt, KdfParams.fromJson(pre.kdf));
  final loginAuthHash = VaultCrypto.bytesToB64(await sha256Bytes(loginKek));
  final matches = loginAuthHash == authHash;
  print('authHash setup  : $authHash');
  print('authHash login  : $loginAuthHash');
  print('KEK coincidente  : $matches');

  final loginSession = await client.login(
    username: username,
    authHashB64: loginAuthHash,
    deviceName: 'e2e',
  );
  print('LOGIN OK: user=${loginSession.user.username}');

  // ==== Unwrap + decrypt del vault (il vero test) ====
  final remote = await client.vaultGet(loginSession.token);
  final unwrapped = await VaultCrypto.unwrapKey(loginKek, remote.wrappedKey);
  final payload = VaultCrypto.decodeJson(
      await VaultCrypto.decrypt(unwrapped, remote.blob, remote.nonce));
  print('VAULT DECRYPT OK: $payload');

  exit(0);
}
