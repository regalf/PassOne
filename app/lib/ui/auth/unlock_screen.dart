import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/biometrics.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../common/cloud_status_icon.dart';

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
      // Re-check server reachability (after the frame, so the provider state
      // isn't modified while the widget tree is building) — the cloud
      // indicator and the offline warning reflect the current state.
      unawaited(ref.read(sessionControllerProvider.notifier).refreshServerStatus());
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

  bool _showOfflineWarning(SessionState session) =>
      session.user != null &&
      session.serverStatus == ServerStatus.offline &&
      !session.settings.hideOfflineWarning;

  Widget _offlineWarningCard(ThemeData theme, SessionState session) {
    final l10n = context.l10n;
    final onContainer = theme.colorScheme.onErrorContainer;
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_off, size: 20, color: onContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.offlineWarningTitle,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: onContainer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.offlineWarningBody,
              style: theme.textTheme.bodySmall?.copyWith(color: onContainer),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: false,
              activeColor: onContainer,
              onChanged: (v) {
                if (v == true) {
                  unawaited(ref
                      .read(sessionControllerProvider.notifier)
                      .setHideOfflineWarning(true));
                }
              },
              title: Text(
                l10n.hideOfflineWarning,
                style:
                    theme.textTheme.bodySmall?.copyWith(color: onContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionControllerProvider);
    final user = session.user;
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(user.username,
                          style: theme.textTheme.bodyMedium),
                      const SizedBox(width: 8),
                      CloudStatusIcon(status: session.serverStatus),
                    ],
                  ),
                ],
                if (_showOfflineWarning(session)) ...[
                  const SizedBox(height: 16),
                  _offlineWarningCard(theme, session),
                ],
                const SizedBox(height: 24),
                TextField(
                  enableIMEPersonalizedLearning: false,
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
