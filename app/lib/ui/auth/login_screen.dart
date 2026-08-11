import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/client.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import 'recover_screen.dart';
import 'register_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;
  String? _showSetupInvite;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = ref.read(sessionControllerProvider);
      if (s.settings.serverUrl.isNotEmpty) {
        _serverController.text = s.settings.serverUrl;
      }
      if (s.settings.lastUsername != null) {
        _usernameController.text = s.settings.lastUsername!;
      }
    });
  }

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final server = _serverController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (server.isEmpty || username.isEmpty || password.isEmpty) {
      setState(() => _error = context.l10n.fillAllFields);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(sessionControllerProvider.notifier).login(
            serverUrl: server,
            username: username,
            password: password,
          );
      ref.read(sessionControllerProvider.notifier).touch();
    } on NeedsSetupException {
      setState(() => _showSetupInvite = username);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on WrongPasswordException {
      if (mounted) setState(() => _error = context.l10n.invalidCredentials);
    } catch (e) {
      if (mounted) setState(() => _error = context.l10n.unexpectedError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final invite = _showSetupInvite;
    if (invite != null) {
      return RegisterScreen(
        serverUrl: _serverController.text.trim(),
        initialUsername: invite,
        inviteMode: true,
        onDone: () {
          setState(() => _showSetupInvite = null);
          ref.read(sessionControllerProvider.notifier).touch();
        },
      );
    }

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.lock_outline,
                    size: 56, color: theme.colorScheme.primary),
                const SizedBox(height: 8),
                Text(context.l10n.appTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text(
                  context.l10n.tagline,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _serverController,
                  decoration: InputDecoration(
                    labelText: context.l10n.serverLabel,
                    hintText: context.l10n.serverHint,
                    prefixIcon: const Icon(Icons.dns_outlined),
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: context.l10n.username,
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  autocorrect: false,
                  enableSuggestions: false,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscure,
                  onSubmitted: (_) => _login(),
                  decoration: InputDecoration(
                    labelText: context.l10n.password,
                    prefixIcon: const Icon(Icons.key_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  SelectableText(_error!,
                      style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _loading ? null : _login,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(context.l10n.signIn),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _loading
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => RegisterScreen(
                                      serverUrl:
                                          _serverController.text.trim(),
                                    )),
                          ),
                  child: Text(context.l10n.createAccount),
                ),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => RecoverScreen(
                                      serverUrl:
                                          _serverController.text.trim(),
                                    )),
                          ),
                  child: Text(context.l10n.forgotRecovery),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
