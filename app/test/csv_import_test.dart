import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:passone_app/ui/settings/import_screen.dart';

void main() {
  test('Bitwarden export file populates entries', () {
    final fixture = File('test/fixtures/bitwarden_export_20260812112049.csv');
    final csv = fixture.existsSync()
        ? fixture.readAsStringSync()
        : 'folder,favorite,type,name,notes,fields,reprompt,'
            'login_uri,login_username,login_password,login_totp\n'
            ',,login,accounts.example.com,,,0,accounts.example.com,,pw1!,\n'
            ',,login,web.fluxer.example,,,0,https://web.fluxer.example,'
            'user@example.com,pw2!,\n'
            ',,login,mpgh.example,,,0,https://www.mpgh.example,'
            'RegakDragoon200,pw3!,\n';
    final vault = importCsv(csv);
    expect(vault.entries.length, 3);
    for (final e in vault.entries) {
      expect(e.name, isNotEmpty);
      expect(e.url, isNotEmpty);
      expect(e.password, isNotEmpty);
    }
    expect(vault.entries.first.username, isEmpty);
    expect(vault.entries[1].username, isNotEmpty);
    expect(vault.entries[2].username, isNotEmpty);
  });

  test('dedicated Bitwarden import skips notes and cards', () {
    const csv = 'folder,favorite,type,name,notes,fields,reprompt,'
        'login_uri,login_username,login_password,login_totp\n'
        ',,login,GitHub,,,0,https://github.com,alice,secret,OTP\n'
        ',,note,My note,hello world,,0,,,,,\n'
        ',,card,Visa,,,0,,,,,\n';
    final vault = importBitwardenCsv(csv);
    expect(vault.entries.length, 1);
    expect(vault.entries.first.name, 'GitHub');
    expect(vault.entries.first.username, 'alice');
    expect(vault.entries.first.password, 'secret');
    expect(vault.entries.first.totpSecret, 'OTP');
  });

  test('dedicated Bitwarden import derives names from the URL', () {
    const csv = 'folder,favorite,type,name,notes,fields,reprompt,'
        'login_uri,login_username,login_password,login_totp\n'
        ',,login,,,0,0,https://web.fluxer.app,user,pw,\n';
    final vault = importBitwardenCsv(csv);
    expect(vault.entries.length, 1);
    expect(vault.entries.first.name, 'Web');
  });

  test('Bitwarden TOTP secrets are normalized on import', () {
    const csv = 'folder,favorite,type,name,notes,fields,reprompt,'
        'login_uri,login_username,login_password,login_totp\n'
        ',,login,GitHub,,,0,https://github.com,alice,secret,'
        'otpauth://totp/GitHub:alice?secret=jbswy3dpehpk3pxp&issuer=GitHub\n';
    final vault = importBitwardenCsv(csv);
    expect(vault.entries.length, 1);
    expect(vault.entries.first.totpSecret, 'JBSWY3DPEHPK3PXP');
  });

  test('invalid TOTP secrets do not break the import', () {
    const csv = 'folder,favorite,type,name,notes,fields,reprompt,'
        'login_uri,login_username,login_password,login_totp\n'
        ',,login,GitHub,,,0,https://github.com,alice,secret,NOT_BASE32!\n';
    final vault = importBitwardenCsv(csv);
    expect(vault.entries.length, 1);
    expect(vault.entries.first.name, 'GitHub');
    expect(vault.entries.first.totpSecret, isNull);
  });

  test('Bitwarden CSV import populates username, password, uri and totp',
      () {
    const csv = 'folder,favorite,type,name,notes,fields,reprompt,'
        'login_uri,login_username,login_password,login_totp\r\n'
        'Social,,login,GitHub,,,0,https://github.com,alice,secret,JBSWY3DPEHPK3PXP\r\n'
        'Work,,login,Email,,,0,https://mail.example.com,bob,hunter2,';
    final vault = importCsv(csv);
    expect(vault.entries.length, 2);

    final gh = vault.entries.first;
    expect(gh.name, 'GitHub');
    expect(gh.url, 'https://github.com');
    expect(gh.username, 'alice');
    expect(gh.password, 'secret');
    expect(gh.totpSecret, 'JBSWY3DPEHPK3PXP');

    final mail = vault.entries.last;
    expect(mail.name, 'Email');
    expect(mail.url, 'https://mail.example.com');
    expect(mail.username, 'bob');
    expect(mail.password, 'hunter2');
    expect(mail.totpSecret, isNull);
  });

  test('plain CSV import still works', () {
    const csv = 'name,url,username,password,notes\n'
        'GitHub,https://github.com,alice,secret,note here';
    final vault = importCsv(csv);
    expect(vault.entries.length, 1);
    expect(vault.entries.first.username, 'alice');
    expect(vault.entries.first.password, 'secret');
    expect(vault.entries.first.notes, 'note here');
  });

  test('Firefox CSV import derives the name from the URL', () {
    const csv = '"url","username","password","httpRealm","formActionOrigin",'
        '"guid","timeCreated","timeLastUsed","timePasswordChanged"\r\n'
        '"https://github.com","alice","secret","","","guid1","1","2","3"\r\n'
        '"https://www.mail.example.com","bob","hunter2","","","guid2","1","2","3"';
    final vault = importCsv(csv);
    expect(vault.entries.length, 2);
    expect(vault.entries.first.name, 'Github');
    expect(vault.entries.first.url, 'https://github.com');
    expect(vault.entries.first.username, 'alice');
    expect(vault.entries.first.password, 'secret');
    expect(vault.entries.last.name, 'Mail');
    expect(vault.entries.last.username, 'bob');
    expect(vault.entries.last.password, 'hunter2');
  });

  test('quoted fields with commas and newlines parse correctly', () {
    const csv = 'name,url,username,password,notes\n'
        '"My, Account",https://x.it,u,p,"line1\nline2"';
    final vault = importCsv(csv);
    expect(vault.entries.length, 1);
    expect(vault.entries.first.name, 'My, Account');
    expect(vault.entries.first.notes, 'line1\nline2');
  });

  test('empty content returns an empty vault', () {
    expect(importCsv('').entries, isEmpty);
  });
}
