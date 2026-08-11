import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../util/password_generator.dart';

/// Dialog per generare una password con opzioni.
class GeneratorDialog extends StatefulWidget {
  final void Function(String password) onGenerated;
  const GeneratorDialog({super.key, required this.onGenerated});

  @override
  State<GeneratorDialog> createState() => _GeneratorDialogState();
}

class _GeneratorDialogState extends State<GeneratorDialog> {
  int _length = 20;
  bool _lower = true;
  bool _upper = true;
  bool _digits = true;
  bool _symbols = true;
  String _preview = '';

  @override
  void initState() {
    super.initState();
    _regenerate();
  }

  void _regenerate() {
    final gen = PasswordGenerator(
      length: _length,
      useLower: _lower,
      useUpper: _upper,
      useDigits: _digits,
      useSymbols: _symbols,
    );
    setState(() => _preview = gen.generate());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.generatorTitle),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    _preview,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 16),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: context.l10n.copy,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _preview));
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(context.l10n.passwordCopied)));
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: context.l10n.regenerate,
                  onPressed: _regenerate,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(context.l10n.length),
                Expanded(
                  child: Slider(
                    value: _length.toDouble(),
                    min: 6,
                    max: 64,
                    divisions: 58,
                    label: '$_length',
                    onChanged: (v) => setState(() {
                      _length = v.round();
                      _regenerate();
                    }),
                  ),
                ),
                Text('$_length'),
              ],
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(context.l10n.uppercase),
              value: _upper,
              onChanged: (v) => setState(() {
                _upper = v!;
                _regenerate();
              }),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(context.l10n.lowercase),
              value: _lower,
              onChanged: (v) => setState(() {
                _lower = v!;
                _regenerate();
              }),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(context.l10n.numbers),
              value: _digits,
              onChanged: (v) => setState(() {
                _digits = v!;
                _regenerate();
              }),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(context.l10n.symbols),
              value: _symbols,
              onChanged: (v) => setState(() {
                _symbols = v!;
                _regenerate();
              }),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            widget.onGenerated(_preview);
            Navigator.of(context).pop();
          },
          child: Text(context.l10n.use),
        ),
      ],
    );
  }
}
