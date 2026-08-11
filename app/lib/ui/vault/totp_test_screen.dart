import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../crypto/models.dart';
import '../../crypto/totp.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';

/// Seed memorizzato in memoria per l'intera durata del processo: viene
/// generato UNA volta per avvio dell'app e riusato a ogni riapertura della
/// pagina, così il QR (e la voce importata nel vault) restano validi.
String? _cachedSeed;

String _buildUri(String secret) =>
    'otpauth://totp/${Uri.encodeComponent('PassOne:Test')}?secret=$secret&issuer=PassOne';

/// Pagina di verifica TOTP: mostra il seed (generato una volta per avvio)
/// come QR otpauth://totp/... e il codice atteso nella stessa finestra di 30s
/// dell'app. Inquadrando il QR col tab TOTP (Aggiungi) la voce importata deve
/// mostrare lo stesso codice di questa pagina.
class TotpTestScreen extends ConsumerStatefulWidget {
  const TotpTestScreen({super.key});

  @override
  ConsumerState<TotpTestScreen> createState() => _TotpTestScreenState();
}

class _TotpTestScreenState extends ConsumerState<TotpTestScreen> {
  late String _secret;
  late String _uri;
  Timer? _ticker;
  String _code = '··· ···';
  int _left = 30;
  final TextEditingController _codeController = TextEditingController();
  bool? _verified;
  bool _added = false;

  @override
  void initState() {
    super.initState();
    if (_cachedSeed == null) {
      final secret = _randomSecret();
      _cachedSeed = secret;
      _secret = secret;
      _uri = _buildUri(secret);
    } else {
      _secret = _cachedSeed!;
      _uri = _buildUri(_cachedSeed!);
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _tick();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  String _randomSecret() {
    final rng = Random.secure();
    final bytes =
        Uint8List.fromList(List.generate(20, (_) => rng.nextInt(256)));
    return base32Encode(bytes);
  }

  void _regenerate() {
    final secret = _randomSecret();
    _cachedSeed = secret;
    setState(() {
      _secret = secret;
      _uri = _buildUri(secret);
      _code = '··· ···';
      _left = 30;
      _verified = null;
      _added = false;
    });
    _tick();
  }

  Future<void> _addToVault() async {
    ref.read(sessionControllerProvider.notifier).touch();
    final notifier = ref.read(sessionControllerProvider.notifier);
    final current = ref.read(sessionControllerProvider).vault;
    final exists =
        current?.entries.any((e) => e.totpSecret == _secret) ?? false;
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.seedAlreadyInVault)));
      return;
    }
    final entry = VaultEntry.create(
      name: 'PassOne: Test',
      notes: 'Seed di test TOTP',
      totpSecret: _secret,
    );
    try {
      await notifier.saveVault(
          VaultData(entries: [...?current?.entries, entry]));
      if (!mounted) return;
      setState(() => _added = true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.totpAdded)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.l10n.errorPrefix(e))));
      }
    }
  }

  Future<void> _tick() async {
    if (!mounted) return;
    final now = DateTime.now();
    final left = totpSecondsLeft(now);
    final code = await generateTotp(_secret, time: now);
    if (!mounted) return;
    setState(() {
      _code = code;
      _left = left;
    });
    // Se è in corso una verifica mostrata, ricalcolala a ogni tick così il
    // responso non resta "vero" quando il codice è già cambiato.
    if (_verified != null) _verify();
  }

  Future<void> _verify() async {
    if (!mounted) return;
    final ok = await verifyTotp(_secret, _codeController.text);
    if (!mounted) return;
    setState(() => _verified = ok);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.totpTestTitle)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: QrImageView(
                data: _uri,
                version: QrVersions.auto,
                size: 220,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              context.l10n.totpScanHint,
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              _code,
              style: theme.textTheme.displayMedium?.copyWith(
                fontFamily: 'monospace',
                letterSpacing: 6,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: _left / 30, minHeight: 6),
          const SizedBox(height: 8),
          Center(
              child:
                  Text(context.l10n.secondsLeft(_left), style: theme.textTheme.bodySmall)),
          const SizedBox(height: 24),
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
                fontFamily: 'monospace', letterSpacing: 4),
            decoration: InputDecoration(
              labelText: context.l10n.verifyField,
              hintText: '••••••',
              counterText: '',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onSubmitted: (_) => _verify(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _verify,
              icon: const Icon(Icons.check_circle_outline),
              label: Text(context.l10n.verify),
            ),
          ),
          const SizedBox(height: 12),
          if (_verified != null)
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_verified! ? Icons.check_circle : Icons.cancel,
                      color: _verified!
                          ? Colors.green
                          : theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Text(
                    _verified! ? context.l10n.codeCorrect : context.l10n.codeWrong,
                    style: TextStyle(
                        color: _verified!
                            ? Colors.green
                            : theme.colorScheme.error,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.seedLabel,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.primary)),
                  const SizedBox(height: 4),
                  SelectableText(_secret,
                      style: const TextStyle(fontFamily: 'monospace')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _regenerate,
            icon: const Icon(Icons.refresh),
            label: Text(context.l10n.newSeed),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _addToVault,
            icon: const Icon(Icons.playlist_add),
            label: Text(
                _added ? context.l10n.addedToVault : context.l10n.addTotpToVault),
          ),
        ],
      ),
    );
  }
}
