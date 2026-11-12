import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:passone_app/api/client.dart';
import 'package:passone_app/crypto/models.dart';
import 'package:passone_app/l10n/app_localizations.dart';
import 'package:passone_app/main.dart';
import 'package:passone_app/state/providers.dart';
import 'package:passone_app/state/session.dart';
import 'package:passone_app/state/settings.dart';
import 'package:passone_app/ui/auth/invite_screen.dart';

/// The invite flow: the user types the invite token, the server resolves it
/// to the account and the app shows which account is being configured, then
/// asks for the master password.
class _InviteController extends SessionController {
  _InviteController({this.registrationAllowed = false})
      : super(SettingsRepository());

  final bool registrationAllowed;

  /// The token the fake server accepts.
  static const validToken = 'valid-token';

  String? registeredUsername;
  String? registeredToken;

  @override
  Future<void> checkServerReachability(String url) async {
    state = state.copyWith(serverAllowRegistration: registrationAllowed);
  }

  @override
  Future<String> lookupInvite(String inviteToken) async {
    if (inviteToken != validToken) {
      throw ApiException(401, 'bad_invite', 'invalid invite token');
    }
    return 'alice';
  }

  @override
  Future<String?> register({
    required String username,
    required String password,
    String? inviteToken,
    bool wantRecovery = false,
    String? serverUrl,
  }) async {
    registeredUsername = username;
    registeredToken = inviteToken;
    state = SessionState(
      status: AuthStatus.unlocked,
      user: UserInfo(
        id: 1,
        username: username,
        status: 'active',
        vaultRevision: 1,
        recoveryEnabled: wantRecovery,
        kdfAlgorithm: 'argon2id',
      ),
      vault: VaultData(),
    );
    return wantRecovery ? 'recovery-fake-123' : null;
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

/// Pumps manually: during the submit the spinner on the button animates
/// forever, so pumpAndSettle would never return.
Future<void> _pumpDialog(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('the token identifies the account, then the password is asked',
      (tester) async {
    final c = _InviteController();
    await tester.pumpWidget(_app(c));
    await tester.pumpAndSettle();

    // The login screen offers the invite token instead of the sign-up form.
    await _fill(tester, 0, 'https://passone.test');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Invite token'), findsOneWidget);
    expect(find.text('Create an account'), findsNothing);

    await tester.tap(find.text('Invite token'));
    await tester.pumpAndSettle();

    // First step: only the token.
    expect(find.text('Set up your account'), findsOneWidget);
    expect(find.text('Invite token'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    // An invalid token is refused and the screen does not advance.
    await _fill(tester, 0, 'wrong-token');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('This invite token is not valid.'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    // A valid token shows the account.
    await _fill(tester, 0, _InviteController.validToken);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Account found'), findsOneWidget);
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('Choose the master password of alice.'), findsOneWidget);
    // The user name is shown, not asked: there are only the two passwords.
    expect(find.byType(TextField), findsNWidgets(2));

    // The password is set with the user name resolved from the token.
    await _fill(tester, 0, 'a-master-password');
    await _fill(tester, 1, 'a-master-password');
    await tester.tap(find.text('Continue'));
    await _pumpDialog(tester);

    expect(c.registeredUsername, 'alice');
    expect(c.registeredToken, _InviteController.validToken);
    expect(find.text('Save your recovery key'), findsOneWidget);
  });

  testWidgets('the passwords must match', (tester) async {
    final c = _InviteController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionControllerProvider.overrideWith((ref) => c)],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: [Locale('en'), Locale('it')],
          home: InviteScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _fill(tester, 0, _InviteController.validToken);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await _fill(tester, 0, 'a-master-password');
    await _fill(tester, 1, 'another-password');
    await tester.tap(find.text('Continue'));
    await _pumpDialog(tester);

    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(c.registeredUsername, isNull);
  });

  testWidgets('with direct registration the sign-up form is offered',
      (tester) async {
    final c = _InviteController(registrationAllowed: true);
    await tester.pumpWidget(_app(c));
    await tester.pumpAndSettle();

    await _fill(tester, 0, 'https://passone.test');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Create an account'), findsOneWidget);
    expect(find.text('Invite token'), findsNothing);
  });
}
