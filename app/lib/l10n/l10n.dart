import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

/// Accesso rapido alle traduzioni: `context.l10n.nomeChiave`.
extension L10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
