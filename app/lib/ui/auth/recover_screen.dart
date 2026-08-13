import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/client.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../state/session.dart';

class RecoverScreen extends ConsumerStatefulWidget {
  final String serverUrl;
  const RecoverScreen({super.key, this.serverUrl = ''});

  @override
  ConsumerState<RecoverScreen> createState() => _RecoverScreenState();
}

class _RecoverScreenState extends ConsumerState<RecoverScreen> {
  final _username = TextEditingController();
  final _recoveryKey = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _wantNewRecovery = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _recoveryKey.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _username.text.trim();
    final recoveryKey = _recoveryKey.text.trim();
    final password = _password.text;
    final confirm = _confirm.text;
    if (username.isEmpty || recoveryKey.isEmpty || password.isEmpty) {
      setState(() => _error = context.l10n.fillAllFields);
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
      final newKey = await ref
          .read(sessionControllerProvider.notifier)
          .recover(
            serverUrl: widget.serverUrl.isEmpty ? null : widget.serverUrl,
            username: username,
            recoveryKey: recoveryKey,
            newPassword: password,
            wantNewRecovery: _wantNewRecovery,
          );
      if (newKey != null) {
        await _showNewRecoveryKey(newKey);
      }
      ref.read(sessionControllerProvider.notifier).touch();
      // Recovery starts from a pushed route (LoginScreen): it returns to the root,
      // where the home screen already shows the unlocked vault.
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on WrongPasswordException {
      if (mounted) setState(() => _error = context.l10n.invalidRecoveryKey);
    } catch (e) {
      if (mounted) setState(() => _error = context.l10n.unexpectedError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showNewRecoveryKey(String key) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
            title: Text(ctx.l10n.newRecoveryKeyTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ctx.l10n.newRecoveryKeyBody,
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
                    key,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(ctx.l10n.savedKeyButton),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.recoverTitle)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.l10n.recoverIntro,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                TextField(
                  enableIMEPersonalizedLearning: false,
                  controller: _username,
                  decoration: InputDecoration(
                    labelText: context.l10n.username,
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  autocorrect: false,
                ),
                const SizedBox(height: 12),
                TextField(
                  enableIMEPersonalizedLearning: false,
                  controller: _recoveryKey,
                  decoration: InputDecoration(
                    labelText: context.l10n.recoveryKey,
                    prefixIcon: const Icon(Icons.vpn_key_outlined),
                  ),
                  autocorrect: false,
                  enableSuggestions: false,
                ),
                const SizedBox(height: 12),
                TextField(
                  enableIMEPersonalizedLearning: false,
                  controller: _password,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: context.l10n.newMasterPassword,
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
                    labelText: context.l10n.confirmPassword,
                    prefixIcon: const Icon(Icons.key_outlined),
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(context.l10n.wantNewRecovery),
                  value: _wantNewRecovery,
                  onChanged: (v) => setState(() => _wantNewRecovery = v!),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  SelectableText(_error!,
                      style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(context.l10n.recoverButton),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
