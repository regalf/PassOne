import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

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

  /// 0 = server address step, 1 = classic login step.
  int _step = 0;

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

  String _normalizeServer(String raw) {
    var s = raw.trim();
    if (!s.contains('://')) s = 'https://$s';
    return s.replaceAll(RegExp(r'/+$'), '');
  }

  bool _looksLikeUrl(String s) {
    final uri = Uri.tryParse(s);
    return uri != null && uri.host.isNotEmpty && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  Future<void> _continue() async {
    final server = _normalizeServer(_serverController.text);
    if (server.isEmpty || !_looksLikeUrl(server)) {
      setState(() => _error = context.l10n.invalidServerUrl);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .checkServerReachability(server);
      await ref.read(sessionControllerProvider.notifier).setServerUrl(server);
      if (mounted) setState(() => _step = 1);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on http.ClientException {
      if (mounted) setState(() => _error = context.l10n.serverUnreachable);
    } on TimeoutException {
      if (mounted) setState(() => _error = context.l10n.serverUnreachable);
    } catch (e) {
      if (mounted) setState(() => _error = context.l10n.serverUnreachable);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

  void _backToServer() {
    setState(() {
      _step = 0;
      _error = null;
    });
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
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _step == 0
                      ? _buildServerStep(theme)
                      : _buildLoginStep(theme),
                ),
              ),
            ),
            Positioned(
              top: 4,
              left: 4,
              right: 4,
              child: Row(
                children: [
                  if (_step == 1)
                    IconButton(
                      tooltip: context.l10n.changeServer,
                      icon: const Icon(Icons.arrow_back),
                      onPressed: _loading ? null : _backToServer,
                    ),
                  const Spacer(),
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: _LanguageDropdown(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerStep(ThemeData theme) {
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.lock_outline, size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 8),
        Text(l10n.appTitle,
            textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(l10n.serverIntro,
            textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        const SizedBox(height: 28),
        TextField(
          controller: _serverController,
          decoration: InputDecoration(
            labelText: l10n.serverLabel,
            hintText: l10n.serverHint,
            prefixIcon: const Icon(Icons.dns_outlined),
          ),
          keyboardType: TextInputType.url,
          autocorrect: false,
          onSubmitted: (_) => _continue(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          SelectableText(_error!,
              style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _loading ? null : _continue,
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.connectButton),
        ),
      ],
    );
  }

  Widget _buildLoginStep(ThemeData theme) {
    final l10n = context.l10n;
    final server = _serverController.text.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.lock_outline, size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 8),
        Text(l10n.appTitle,
            textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(server,
            textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        const SizedBox(height: 28),
        TextField(
          controller: _usernameController,
          decoration: InputDecoration(
            labelText: l10n.username,
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
            labelText: l10n.password,
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
              : Text(l10n.signIn),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _loading
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => RegisterScreen(
                              serverUrl: server,
                            )),
                  ),
          child: Text(l10n.createAccount),
        ),
        TextButton(
          onPressed: _loading
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => RecoverScreen(
                              serverUrl: server,
                            )),
                  ),
          child: Text(l10n.forgotRecovery),
        ),
      ],
    );
  }
}

/// Small language selector shown in the top-right corner of the login screen.
class _LanguageDropdown extends ConsumerWidget {
  const _LanguageDropdown();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(sessionControllerProvider).settings;
    final value = settings.languageCode ?? 'system';
    return DropdownButton<String>(
      value: value,
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(8),
      onChanged: (v) => ref
          .read(sessionControllerProvider.notifier)
          .setLanguageCode(v == 'system' ? null : v),
      items: [
        DropdownMenuItem(value: 'system', child: Text(l10n.languageSystem)),
        DropdownMenuItem(value: 'it', child: Text(l10n.italian)),
        DropdownMenuItem(value: 'en', child: Text(l10n.english)),
      ],
    );
  }
}
