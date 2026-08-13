import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/biometrics.dart';
import '../../state/providers.dart';
import '../../state/session.dart';

/// Unlock screen: requires the master password to decrypt the local vault.
class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  bool _autoPrompted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // As soon as the lock screen appears, if biometrics are enabled the prompt
    // fires on its own (once per screen) — unless the vault was locked
    // manually with the Lock button, in which case the user must explicitly
    // choose to unlock (password or fingerprint button).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _autoPrompted) return;
      final notifier = ref.read(sessionControllerProvider.notifier);
      final manualLock = notifier.consumeManualLock();
      final enabled =
          ref.read(sessionControllerProvider).settings.biometricsEnabled;
      if (enabled && !manualLock) {
        _autoPrompted = true;
        _unlockWithBiometrics();
      }
    });
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final password = _password.text;
    if (password.isEmpty) {
      setState(() => _error = context.l10n.enterPassword);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(sessionControllerProvider.notifier).unlock(password);
      ref.read(sessionControllerProvider.notifier).touch();
    } on WrongPasswordException {
      if (mounted) setState(() => _error = context.l10n.invalidPassword);
    } catch (e) {
      if (mounted) setState(() => _error = context.l10n.errorPrefix(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unlockWithBiometrics() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await ref
        .read(sessionControllerProvider.notifier)
        .unlockWithBiometrics();
    if (!mounted) return;
    switch (result) {
      case BiometricReadResult.success:
        ref.read(sessionControllerProvider.notifier).touch();
      case BiometricReadResult.canceled:
        setState(() => _error = context.l10n.bioCanceled);
      case BiometricReadResult.unavailable:
        setState(() => _error = context.l10n.bioUnavailable);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(sessionControllerProvider).user;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock,
                    size: 56, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text(context.l10n.unlockTitle,
                    style: theme.textTheme.headlineSmall),
                if (user != null) ...[
                  const SizedBox(height: 4),
                  Text(user.username,
                      style: theme.textTheme.bodyMedium),
                ],
                const SizedBox(height: 24),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  autofocus: true,
                  onSubmitted: (_) => _unlock(),
                  decoration: InputDecoration(
                    labelText: context.l10n.masterPassword,
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
                  onPressed: _loading ? null : _unlock,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(context.l10n.unlockButton),
                ),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () async {
                          await ref
                              .read(sessionControllerProvider.notifier)
                              .logout();
                        },
                  child: Text(context.l10n.logout),
                ),
                if (ref.watch(sessionControllerProvider).settings.biometricsEnabled) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _unlockWithBiometrics,
                    icon: const Icon(Icons.fingerprint),
                    label: Text(context.l10n.unlockBiometric),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
