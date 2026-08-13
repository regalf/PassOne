import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:passone_app/api/client.dart';
import 'package:passone_app/crypto/models.dart';
import 'package:passone_app/main.dart';
import 'package:passone_app/state/biometrics.dart';
import 'package:passone_app/state/providers.dart';
import 'package:passone_app/state/session.dart';
import 'package:passone_app/state/settings.dart';

/// RFC 6238 TOTP computed INDEPENDENTLY of the app: it uses package:crypto
/// (HMAC-SHA1 different from package:cryptography). It verifies that the code
/// shown by the app is actually the correct one for the current time.
String referenceTotp(Uint8List secret, {required DateTime time}) {
  final counter = (time.millisecondsSinceEpoch ~/ 1000) ~/ 30;
  final msg = ByteData(8)..setUint64(0, counter);
  final h = Hmac(sha1, secret).convert(msg.buffer.asUint8List()).bytes;
  final offset = h[h.length - 1] & 0x0f;
  final bin = ((h[offset] & 0x7f) << 24) |
      ((h[offset + 1] & 0xff) << 16) |
      ((h[offset + 2] & 0xff) << 8) |
      (h[offset + 3] & 0xff);
  return (bin % 1000000).toString().padLeft(6, '0');
}

/// True if [code] is the RFC 6238 code of the current window (with a
/// tolerance of 1 window for the edge case where the interval changes
/// mid-test).
bool matchesAnyWindow(String code, Uint8List secret, DateTime now) {
  for (final i in [-1, 0, 1]) {
    if (referenceTotp(secret, time: now.add(Duration(seconds: i * 30))) ==
        code) {
      return true;
    }
  }
  return false;
}

/// Fake controller: registration/recovery without network, returns a fake
/// recovery key and moves the state to "unlocked".
class _FakeController extends SessionController {
  _FakeController() : super(SettingsRepository());
  SessionState _unlocked(String username, {required bool recovery}) =>
      SessionState(
        status: AuthStatus.unlocked,
        user: UserInfo(
          id: 1,
          username: username,
          status: 'active',
          vaultRevision: 1,
          recoveryEnabled: recovery,
          kdfAlgorithm: 'argon2id',
        ),
        vault: VaultData(),
      );
  @override
  Future<String?> register({
    required String username,
    required String password,
    String? inviteToken,
    bool wantRecovery = false,
    String? serverUrl,
  }) async {
    state = _unlocked(username, recovery: wantRecovery);
    return wantRecovery ? 'recovery-fake-123' : null;
  }
  @override
  Future<String?> recover({
    required String username,
    required String recoveryKey,
    required String newPassword,
    bool wantNewRecovery = false,
    String? serverUrl,
  }) async {
    state = _unlocked(username, recovery: wantNewRecovery);
    return wantNewRecovery ? 'recovery-fake-new' : null;
  }
  @override
  Future<void> logout() async {
    state = const SessionState();
  }
  @override
  Future<void> checkServerReachability(String url) async {}
  @override
  Future<void> logoutAll() async {
    state = const SessionState();
  }
  @override
  void touch() {}
}

/// Fake with an initial "locked" state and biometrics active:
/// `unlockWithBiometrics` counts the calls (to verify the automatic prompt)
/// and unlocks.
class _FakeBiometricsController extends SessionController {
  _FakeBiometricsController()
      : super(SettingsRepository());
  int bioCalls = 0;
  void startUnlocked() {
    state = SessionState(
      status: AuthStatus.unlocked,
      settings: const AppSettings(biometricsEnabled: true),
      user: UserInfo(
        id: 1,
        username: 'dave',
        status: 'active',
        vaultRevision: 1,
        recoveryEnabled: false,
        kdfAlgorithm: 'argon2id',
      ),
      vault: VaultData(),
      vaultKey: Uint8List(32),
    );
  }
  void startLocked() {
    state = SessionState(
      status: AuthStatus.locked,
      settings: const AppSettings(biometricsEnabled: true),
      user: UserInfo(
        id: 1,
        username: 'dave',
        status: 'active',
        vaultRevision: 1,
        recoveryEnabled: false,
        kdfAlgorithm: 'argon2id',
      ),
      cache: CachedVault(
        token: 'cache-token',
        userId: 1,
        username: 'dave',
        salt: Uint8List(16),
        kdf: const {'algorithm': 'argon2id', 'memoryKiB': 19456},
        wrappedKey: Uint8List(48),
        wrappedRecovery: null,
        blob: Uint8List(16),
        nonce: Uint8List(12),
        revision: 1,
      ),
    );
  }
  @override
  Future<BiometricReadResult> unlockWithBiometrics() async {
    bioCalls++;
    final s = state;
    if (s.status != AuthStatus.locked) return BiometricReadResult.unavailable;
    state = s.copyWith(
      status: AuthStatus.unlocked,
      vault: VaultData(),
      vaultKey: Uint8List(32),
    );
    return BiometricReadResult.success;
  }
  @override
  void touch() {}
}

/// Fake that starts "unlocked" with a vault (to test the vault tabs).
class _FakeVaultController extends SessionController {
  _FakeVaultController() : super(SettingsRepository());
  void start({List<VaultEntry> entries = const []}) {
    state = SessionState(
      status: AuthStatus.unlocked,
      user: UserInfo(
        id: 1,
        username: 'dave',
        status: 'active',
        vaultRevision: 1,
        recoveryEnabled: false,
        kdfAlgorithm: 'argon2id',
      ),
      vault: VaultData(entries: entries),
      vaultKey: Uint8List(32),
    );
  }
  @override
  void touch() {}
  @override
  Future<void> checkServerReachability(String url) async {}
  @override
  Future<void> saveVault(VaultData vault) async {
    state = state.copyWith(vault: vault);
  }
}

/// Like [_FakeController] but the server is never reachable.
class _UnreachableController extends _FakeController {
  @override
  Future<void> checkServerReachability(String url) async {
    throw http.ClientException('connection refused');
  }
}

Widget _app(SessionController c) => ProviderScope(
      overrides: [
        sessionControllerProvider.overrideWith((ref) => c),
      ],
      child: const PassOneApp(),
    );

Future<void> _fill(WidgetTester tester, int index, String text) async {
  await tester.enterText(find.byType(TextField).hitTestable().at(index), text);
}

/// First step of the login flow: enters the server address and continues
/// to the classic login screen.
Future<void> _connectToServer(WidgetTester tester,
    {String server = 'https://passone.test'}) async {
  await _fill(tester, 0, server);
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
}

/// Pumps manually: during submit the spinner on the button animates forever
/// and pumpAndSettle never converges. The dialog opens in ~2 frames.
Future<void> _pumpDialog(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  testWidgets('after registration you return to the vault home',
      (tester) async {
    final c = _FakeController();
    await tester.pumpWidget(_app(c));
    await tester.pumpAndSettle();
    expect(find.text('Continue'), findsOneWidget,
        reason: 'the login starts with the server address step');
    await _connectToServer(tester);
    expect(find.text('Sign in'), findsOneWidget);
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    await _fill(tester, 0, 'alice');
    await _fill(tester, 1, 'test-password');
    await _fill(tester, 2, 'test-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await _pumpDialog(tester);
    expect(find.text('Save your recovery key'), findsOneWidget);
    await tester.tap(find.text('I saved the key'));
    await tester.pumpAndSettle();
    expect(find.text('Save your recovery key'), findsNothing);
    expect(find.text('Create account'), findsNothing);
    expect(find.widgetWithText(FloatingActionButton, 'New'), findsOneWidget);
  });
  testWidgets('an unreachable server shows an error and stays on the '
      'server step', (tester) async {
    final c = _UnreachableController();
    await tester.pumpWidget(_app(c));
    await tester.pumpAndSettle();
    await _fill(tester, 0, 'https://unreachable.test');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(
      find.text(
          'Could not reach the server. Check the address and your connection.'),
      findsOneWidget,
    );
    expect(find.text('Sign in'), findsNothing,
        reason: 'the flow must not advance to the login step');
  });
  testWidgets('logout returns to the login screen', (tester) async {
    final c = _FakeController();
    await tester.pumpWidget(_app(c));
    await tester.pumpAndSettle();
    await _connectToServer(tester);
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    await _fill(tester, 0, 'bob');
    await _fill(tester, 1, 'test-password');
    await _fill(tester, 2, 'test-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await _pumpDialog(tester);
    await tester.tap(find.text('I saved the key'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Server address'), findsOneWidget,
        reason: 'the settings tab shows its content');
    await tester.scrollUntilVisible(find.text('Log out'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Log out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    expect(find.text('Continue'), findsOneWidget,
        reason: 'after logout the login restarts from the server step');
    expect(find.widgetWithText(FloatingActionButton, 'New'), findsNothing);
  });
  testWidgets('account recovery returns to the vault home', (tester) async {
    final c = _FakeController();
    await tester.pumpWidget(_app(c));
    await tester.pumpAndSettle();
    await _connectToServer(tester);
    await tester.tap(find.text('Forgot password? Use recovery key'));
    await tester.pumpAndSettle();
    await _fill(tester, 0, 'carol');
    await _fill(tester, 1, 'recovery-fake-999');
    await _fill(tester, 2, 'new-password');
    await _fill(tester, 3, 'new-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Recover account'));
    await _pumpDialog(tester);
    expect(find.text('New recovery key'), findsOneWidget);
    await tester.tap(find.text('I saved the key'));
    await tester.pumpAndSettle();
    expect(find.text('Account recovery'), findsNothing);
    expect(find.widgetWithText(FloatingActionButton, 'New'), findsOneWidget);
  });
  testWidgets('with lock active, the biometric prompt starts by itself '
      'and unlocks only on success', (tester) async {
    final c = _FakeBiometricsController();
    // Let _init() complete (it moves the state to "unauthenticated") before
    // setting the fake to the "locked" state with biometrics active.
    await tester.pumpWidget(_app(c));
    await tester.pumpAndSettle();
    expect(find.text('Continue'), findsOneWidget,
        reason: 'the login starts with the server address step');
    c.startLocked();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(c.bioCalls, 1,
        reason: 'the prompt must start without touching the button');
    expect(find.text('Vault locked'), findsNothing);
    expect(find.widgetWithText(FloatingActionButton, 'New'), findsOneWidget);
  });
  testWidgets('the Lock button locks and does not fire the biometric prompt',
      (tester) async {
    final c = _FakeBiometricsController();
    await tester.pumpWidget(_app(c));
    await tester.pumpAndSettle();
    c.startUnlocked();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FloatingActionButton, 'New'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.lock_outline));
    await tester.pumpAndSettle();
    expect(c.bioCalls, 0,
        reason: 'a manual lock must not start the prompt automatically');
    expect(find.text('Vault locked'), findsOneWidget,
        reason: 'after a manual lock the vault stays on the unlock screen');
    expect(find.widgetWithText(FloatingActionButton, 'New'), findsNothing);
  });
  testWidgets('the FAB adapts to the open list (New on home, Add on TOTP)',
      (tester) async {
    final c = _FakeVaultController();
    await tester.pumpWidget(_app(c));
    await tester.pumpAndSettle();
    c.start(entries: [
      VaultEntry.create(
          name: 'GitHub',
          totpSecret: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'),
    ]);
    await tester.pump();
    expect(find.widgetWithText(FloatingActionButton, 'New'), findsOneWidget);
    await tester.tap(find.text('TOTP'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FloatingActionButton, 'Add').hitTestable(),
        findsOneWidget);
    expect(find.widgetWithText(FloatingActionButton, 'New').hitTestable(),
        findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Passwords'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FloatingActionButton, 'New').hitTestable(),
        findsOneWidget);
    expect(find.widgetWithText(FloatingActionButton, 'Add').hitTestable(),
        findsNothing);
  });
  testWidgets('the TOTP list shows the 6-digit code and the countdown',
      (tester) async {
    final c = _FakeVaultController();
    await tester.pumpWidget(_app(c));
    await tester.pumpAndSettle();
    c.start(entries: [
      VaultEntry.create(
          name: 'GitHub',
          totpSecret: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'),
    ]);
    await tester.pump();
    await tester.tap(find.text('TOTP'));
    await tester.pumpAndSettle();
    // Let generateTotp (microtask) and the first refresh complete.
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('GitHub'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^\d{6}$')), findsOneWidget,
        reason: 'a 6-digit TOTP code must be visible');
    expect(find.textContaining(RegExp(r'^\d+ s$')), findsOneWidget,
        reason: 'the countdown in seconds must be visible');
  });
  testWidgets('the displayed code is correct (independent RFC 6238) '
      'and copies on tap', (tester) async {
    const secretB32 = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
    final secret = Uint8List.fromList('12345678901234567890'.codeUnits);
    final c = _FakeVaultController();
    await tester.pumpWidget(_app(c));
    await tester.pumpAndSettle();
    c.start(entries: [
      VaultEntry.create(name: 'GitHub', totpSecret: secretB32),
    ]);
    await tester.pump();
    await tester.tap(find.text('TOTP'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 50));
    final codeFinder = find.textContaining(RegExp(r'^\d{6}$'));
    expect(codeFinder, findsOneWidget);
    final displayed = tester.widget<Text>(codeFinder).data!;
    expect(matchesAnyWindow(displayed, secret, DateTime.now()), isTrue,
        reason: 'the on-screen code ($displayed) does not match RFC 6238');
    // Mock the clipboard: capture what the app copies when the code is tapped.
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    await tester.tap(codeFinder);
    await tester.pump();
    expect(copied, isNotNull, reason: 'the tap must copy the code');
    expect(matchesAnyWindow(copied!, secret, DateTime.now()), isTrue,
        reason: 'the copied code ($copied) does not match RFC 6238');
  });
  testWidgets('an SSH key can be added from the SSH list and appears in the '
      'list', (tester) async {
    final c = _FakeVaultController();
    await tester.pumpWidget(_app(c));
    await tester.pumpAndSettle();
    c.start();
    await tester.pump();
    await tester.tap(find.text('SSH'));
    await tester.pumpAndSettle();
    expect(find.text('No SSH keys.\nPress "New" to add a key.'),
        findsOneWidget);
    await tester
        .tap(find.widgetWithText(FloatingActionButton, 'New').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('New SSH key'), findsOneWidget);
    await _fill(tester, 0, 'work-key');
    await _fill(tester, 1, 'github.com');
    await _fill(tester, 2, 'git');
    await _fill(tester, 3,
        '-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('work-key'), findsOneWidget);
    expect(find.text('git @ github.com'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Passwords'));
    await tester.pumpAndSettle();
    expect(find.text('work-key'), findsNothing,
        reason: 'SSH keys must not appear in the Passwords list');
  });
}
