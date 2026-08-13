import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/app_localizations.dart';
import 'l10n/l10n.dart';
import 'state/providers.dart';
import 'state/session.dart';
import 'ui/auth/login_screen.dart';
import 'ui/auth/unlock_screen.dart';
import 'ui/vault/vault_screen.dart';

void main() {
  runApp(const ProviderScope(child: PassOneApp()));
}

class PassOneApp extends ConsumerWidget {
  const PassOneApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final languageCode = ref.watch(sessionControllerProvider).settings.languageCode;
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        // On Android 12+ follows the system accent (Material You); elsewhere
        // uses the PassOne green as fallback.
        final lightScheme = lightDynamic ??
            ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32));
        final darkScheme = darkDynamic ??
            ColorScheme.fromSeed(
              seedColor: const Color(0xFF2E7D32),
              brightness: Brightness.dark,
            );
        return MaterialApp(
          title: 'PassOne',
          debugShowCheckedModeBanner: false,
          onGenerateTitle: (ctx) => ctx.l10n.appTitle,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('it'), Locale('en')],
          locale: languageCode == null ? null : Locale(languageCode),
          localeResolutionCallback: (deviceLocale, supportedLocales) {
            if (deviceLocale != null && deviceLocale.languageCode == 'it') {
              return const Locale('it');
            }
            return const Locale('en');
          },
          theme: ThemeData(
            colorScheme: lightScheme,
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: darkScheme,
            useMaterial3: true,
          ),
          themeMode: ThemeMode.system,
          home: const _Root(),
        );
      },
    );
  }
}

/// Picks the screen based on the session state.
class _Root extends ConsumerStatefulWidget {
  const _Root();

  @override
  ConsumerState<_Root> createState() => _RootState();
}

class _RootState extends ConsumerState<_Root> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) {
      ref.read(sessionControllerProvider.notifier).checkResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    // When the session leaves "unlocked" (logout, logout-all, lock) the
    // routes pushed on top of the Navigator (e.g. Settings) must be removed to
    // go back to the base screen (login or unlock).
    ref.listen<SessionState>(sessionControllerProvider, (prev, next) {
      if (prev != null &&
          prev.status != next.status &&
          (next.status == AuthStatus.unauthenticated ||
              next.status == AuthStatus.locked)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          Navigator.of(context, rootNavigator: true)
              .popUntil((route) => route.isFirst);
        });
      }
    });
    switch (session.status) {
      case AuthStatus.unauthenticated:
        return const LoginScreen();
      case AuthStatus.locked:
        return const UnlockScreen();
      case AuthStatus.unlocked:
        return const VaultScreen();
    }
  }
}
