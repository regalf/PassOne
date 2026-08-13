import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:passone_app/crypto/models.dart';
import 'package:passone_app/crypto/passone_file.dart';

VaultData _sampleVault() => VaultData(entries: [
      VaultEntry.create(
          name: 'GitHub',
          url: 'https://github.com',
          username: 'alice',
          password: 'secret',
          totpSecret: 'JBSWY3DPEHPK3PXP',
          privateKey: '-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----'),
      VaultEntry.create(name: 'Work', username: 'bob', password: 'hunter2'),
    ]);

void main() {
  test('encrypt/decrypt roundtrip restores the vault', () async {
    final envelope = await PassoneFile.encrypt(_sampleVault(), 'export-password');
    final map = jsonDecode(envelope) as Map<String, dynamic>;
    expect(map['format'], 'passone');
    expect(map['version'], 1);
    expect(map['data_b64'], isNotEmpty);

    final restored = await PassoneFile.decrypt(envelope, 'export-password');
    expect(restored.entries.length, 2);
    final gh = restored.entries.firstWhere((e) => e.name == 'GitHub');
    expect(gh.username, 'alice');
    expect(gh.password, 'secret');
    expect(gh.totpSecret, 'JBSWY3DPEHPK3PXP');
    expect(gh.privateKey, contains('OPENSSH PRIVATE KEY'));
  });

  test('the envelope does not contain plaintext data', () async {
    final envelope = await PassoneFile.encrypt(_sampleVault(), 'export-password');
    expect(envelope, isNot(contains('secret')));
    expect(envelope, isNot(contains('hunter2')));
    expect(envelope, isNot(contains('JBSWY3DPEHPK3PXP')));
  });

  test('a wrong password fails with PassoneDecryptException', () async {
    final envelope = await PassoneFile.encrypt(_sampleVault(), 'right-password');
    await expectLater(
      PassoneFile.decrypt(envelope, 'wrong-password'),
      throwsA(isA<PassoneDecryptException>()),
    );
  });

  test('an empty password fails', () async {
    final envelope = await PassoneFile.encrypt(_sampleVault(), 'x');
    await expectLater(
      PassoneFile.decrypt(envelope, ''),
      throwsA(isA<PassoneDecryptException>()),
    );
  });

  test('non-PassOne content fails with PassoneDecryptException', () async {
    await expectLater(
      PassoneFile.decrypt('{"foo": 1}', 'any'),
      throwsA(isA<PassoneDecryptException>()),
    );
    await expectLater(
      PassoneFile.decrypt('not json at all', 'any'),
      throwsA(isA<PassoneDecryptException>()),
    );
  });

  test('a corrupted ciphertext fails', () async {
    final envelope = await PassoneFile.encrypt(_sampleVault(), 'x');
    final map = jsonDecode(envelope) as Map<String, dynamic>;
    map['data_b64'] = 'AAAA${(map['data_b64'] as String).substring(4)}';
    await expectLater(
      PassoneFile.decrypt(jsonEncode(map), 'x'),
      throwsA(isA<PassoneDecryptException>()),
    );
  });

  test('isPassoneEnvelope detects the envelope regardless of the file name',
      () async {
    final envelope = await PassoneFile.encrypt(_sampleVault(), 'pw');
    expect(PassoneFile.isPassoneEnvelope(envelope), isTrue);
  });

  test('isPassoneEnvelope rejects plain JSON, CSV and garbage', () async {
    expect(PassoneFile.isPassoneEnvelope(
            '{"version":1,"entries":[{"name":"x"}]}'),
        isFalse);
    expect(PassoneFile.isPassoneEnvelope('name,url\nfoo,bar'), isFalse);
    expect(PassoneFile.isPassoneEnvelope('not json at all'), isFalse);
    expect(PassoneFile.isPassoneEnvelope(''), isFalse);
  });
}
