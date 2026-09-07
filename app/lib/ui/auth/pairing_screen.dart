import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/client.dart';
import '../../api/tls.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../vault/qr_scanner_screen.dart';

/// TLS pairing screen shown when the server uses a self-signed certificate
/// (or its certificate changed): the user scans the QR / types the pairing
/// code shown by the server, and the app pins the SPKI fingerprint.
///
/// Pops `true` when the pairing was saved (the caller re-runs the step that
/// needed the trusted connection). Layout follows the design sketch: title and
/// divider on top, explanation, code box, primary "scan QR" button.
class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({
    super.key,
    required this.serverUrl,
    this.mismatch = false,
  });

  final String serverUrl;

  /// True when the previous pairing pin no longer matches the certificate
  /// (e.g. after `passone tls rotate`): the screen warns and asks for the new
  /// code.
  final bool mismatch;

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<bool> _scan() async {
    final l10n = context.l10n;
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => QrScannerScreen(
          accept: (raw) => pairingCodeFromQrText(raw) != null,
        ),
      ),
    );
    if (scanned == null || !mounted) return false;
    final code = pairingCodeFromQrText(scanned);
    if (code == null) {
      // The scanner only stops on accepted barcodes, so this is defensive.
      setState(() => _error = l10n.invalidPairingCode);
      return false;
    }
    setState(() {
      _codeController.text = code;
    });
    return _pair(code);
  }

  Future<bool> _submit(String raw) async {
    final code = normalizePairingCode(raw);
    if (code == null) {
      setState(() => _error = context.l10n.invalidPairingCode);
      return false;
    }
    return _pair(code);
  }

  Future<bool> _pair(String code) async {
    final l10n = context.l10n;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .pair(url: widget.serverUrl, code: code);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.pairingSuccess)));
        // Pop with `true` so the caller (login screen) re-runs the step that
        // needed the trusted connection and lands on the login step.
        Navigator.of(context).pop(true);
      }
      return true;
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return false;
    } catch (_) {
      if (mounted) setState(() => _error = l10n.unexpectedError('pairing'));
      return false;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Forgets the saved pin and returns: the caller retries the connection,
  /// which now reports "pairing required" again and reopens this screen in the
  /// clean (non-mismatch) state for the fresh code.
  Future<void> _forget() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await ref.read(sessionControllerProvider.notifier).clearPin();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    }
  }

  void _leave() {
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Text(l10n.pairingTitle,
                  style: theme.textTheme.headlineMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Divider(color: theme.colorScheme.outlineVariant),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.mismatch)
                        Card(
                          color: theme.colorScheme.errorContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l10n.certChangedTitle,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                        color:
                                            theme.colorScheme.onErrorContainer)),
                                const SizedBox(height: 8),
                                Text(l10n.certChangedBody,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                        color:
                                            theme.colorScheme.onErrorContainer)),
                              ],
                            ),
                          ),
                        ),
                      Text(
                        l10n.pairingIntro,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.pairingContact,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        enableIMEPersonalizedLearning: false,
                        controller: _codeController,
                        decoration: InputDecoration(
                          labelText: l10n.pairingCodeLabel,
                          hintText: l10n.pairingCodeHint,
                          prefixIcon: const Icon(Icons.vpn_key_outlined),
                        ),
                        keyboardType: TextInputType.text,
                        autocorrect: false,
                        enableSuggestions: false,
                        textCapitalization: TextCapitalization.none,
                        onSubmitted: (_) => _submit(_codeController.text),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        SelectableText(_error!,
                            style: TextStyle(color: theme.colorScheme.error)),
                      ],
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _loading ? null : _scan,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: Text(l10n.scanPairingQr),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonal(
                        onPressed: _loading
                            ? null
                            : () => _submit(_codeController.text),
                        child: Text(l10n.pairingContinue),
                      ),
                      if (widget.mismatch) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _loading ? null : _forget,
                          child: Text(l10n.forgetServer),
                        ),
                      ],
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _loading ? null : _leave,
                        child: Text(context.l10n.close),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}