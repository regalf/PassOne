import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/client.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  final String serverUrl;
  final String? initialUsername;
  final bool inviteMode;
  final VoidCallback? onDone;

  const RegisterScreen({
    super.key,
    this.serverUrl = '',
    this.initialUsername,
    this.inviteMode = false,
    this.onDone,
  });

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _username = TextEditingController();
  final _invite = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _wantRecovery = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _username.text = widget.initialUsername ?? '';
  }

  @override
  void dispose() {
    _username.dispose();
    _invite.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _username.text.trim();
    final password = _password.text;
    final confirm = _confirm.text;
    if (username.isEmpty || password.isEmpty) {
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
      final recoveryKey = await ref.read(sessionControllerProvider.notifier).register(
            serverUrl: widget.serverUrl.isEmpty ? null : widget.serverUrl,
            username: username,
            password: password,
            inviteToken: _invite.text.trim().isEmpty
                ? null
                : _invite.text.trim(),
            wantRecovery: _wantRecovery,
          );
      if (recoveryKey != null) {
        await _showRecoveryKey(recoveryKey);
      }
      widget.onDone?.call();
      // Se la registrazione è avvenuta da una route spinta (LoginScreen ->
      // Crea account), torna alla radice: la home mostra già il vault.
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = context.l10n.unexpectedError(e));
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
              setState(() =>
                  _error = ctx.l10n.recoveryGeneratedNotice);
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
    return Scaffold(
      appBar: AppBar(
          title: Text(
              widget.inviteMode ? context.l10n.registerFirstAccess : context.l10n.registerTitle)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _username,
                  decoration: InputDecoration(
                    labelText: context.l10n.username,
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  autocorrect: false,
                  enableSuggestions: false,
                ),
                const SizedBox(height: 12),
                if (widget.inviteMode) ...[
                  TextField(
                    controller: _invite,
                    decoration: InputDecoration(
                      labelText: context.l10n.inviteToken,
                      prefixIcon: const Icon(Icons.confirmation_number_outlined),
                    ),
                    autocorrect: false,
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _password,
                  obscureText: _obscure,
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
                const SizedBox(height: 12),
                TextField(
                  controller: _confirm,
                  obscureText: _obscure,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: context.l10n.confirmMasterPassword,
                    prefixIcon: const Icon(Icons.key_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(context.l10n.wantRecovery),
                  subtitle: Text(context.l10n.wantRecoverySub),
                  value: _wantRecovery,
                  onChanged: (v) => setState(() => _wantRecovery = v!),
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
                      : Text(context.l10n.submitRegistration),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
