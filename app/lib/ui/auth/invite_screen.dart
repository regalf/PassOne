import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/client.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';

/// Setup of an account created with an invite token.
///
/// The user only has to type the token: it identifies the account, so the
/// user name cannot be mistyped. The server resolves it and the second step
/// shows which account is being configured, then asks for the master
/// password.
class InviteScreen extends ConsumerStatefulWidget {
  final String serverUrl;
  final VoidCallback? onDone;

  const InviteScreen({super.key, this.serverUrl = '', this.onDone});

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  final _token = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  /// The account the token belongs to, resolved in the first step.
  String? _username;
  bool _obscure = true;
  bool _wantRecovery = true;
  bool _loading = false;
  String? _error;

  bool get _onTokenStep => _username == null;

  @override
  void dispose() {
    _token.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// First step: the token identifies the account.
  Future<void> _lookupToken() async {
    final token = _token.text.trim();
    if (token.isEmpty) {
      setState(() => _error = context.l10n.fillAllFields);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final username =
          await ref.read(sessionControllerProvider.notifier).lookupInvite(token);
      if (!mounted) return;
      setState(() => _username = username);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.code == 'bad_invite'
          ? context.l10n.inviteTokenInvalid
          : e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = context.l10n.unexpectedError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Second step: the master password of the account found with the token.
  Future<void> _submit() async {
    final username = _username;
    final password = _password.text;
    final confirm = _confirm.text;
    if (username == null || password.isEmpty) {
      setState(() => _error = context.l10n.fillUserPass);
      return;
    }
    if (password.length < 8) {
      setState(() => _error = context.l10n.passwordTooShort);
      return;
    }
    if (password != confirm) {
      setState(() => _error = context.l10n.passwordsDiffer);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final recoveryKey = await ref
          .read(sessionControllerProvider.notifier)
          .register(
            serverUrl: widget.serverUrl.isEmpty ? null : widget.serverUrl,
            username: username,
            password: password,
            inviteToken: _token.text.trim(),
            wantRecovery: _wantRecovery,
          );
      if (recoveryKey != null) {
        await _showRecoveryKey(recoveryKey);
      }
      widget.onDone?.call();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = context.l10n.unexpectedError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showRecoveryKey(String recoveryKey) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
            title: Text(ctx.l10n.recoveryKeyTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ctx.l10n.recoveryKeyBody,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    recoveryKey,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  setState(() => _error = ctx.l10n.recoveryGeneratedNotice);
                },
                child: Text(ctx.l10n.savedKeyButton),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.inviteTitle)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_onTokenStep) ...[
                  // The action is at the top: the token is the only thing
                  // to fill in on this step.
                  FilledButton(
                    onPressed: _loading ? null : _lookupToken,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.inviteContinue),
                  ),
                  const SizedBox(height: 20),
                  Text(l10n.inviteStepTokenIntro,
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  TextField(
                    enableIMEPersonalizedLearning: false,
                    controller: _token,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _lookupToken(),
                    decoration: InputDecoration(
                      labelText: l10n.inviteStepToken,
                      prefixIcon: const Icon(Icons.confirmation_number_outlined),
                    ),
                  ),
                ] else ...[
                  Row(
                    children: [
                      Icon(Icons.check_circle_outline,
                          color: theme.colorScheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(l10n.inviteAccountFound,
                          style: theme.textTheme.labelLarge),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // The account comes from the token: it is shown, not typed.
                  InputDecorator(
                    decoration: InputDecoration(
                      labelText: l10n.inviteUsernameLabel,
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                    child: Text(_username!,
                        style: theme.textTheme.titleMedium),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.invitePasswordIntro(_username!),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    enableIMEPersonalizedLearning: false,
                    controller: _password,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: l10n.masterPassword,
                      prefixIcon: const Icon(Icons.key_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    enableIMEPersonalizedLearning: false,
                    controller: _confirm,
                    obscureText: _obscure,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: l10n.confirmMasterPassword,
                      prefixIcon: const Icon(Icons.key_outlined),
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(l10n.wantRecovery),
                    subtitle: Text(l10n.wantRecoverySub),
                    value: _wantRecovery,
                    onChanged: (v) => setState(() => _wantRecovery = v!),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.inviteContinue),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  SelectableText(_error!,
                      style: TextStyle(color: theme.colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
