import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

/// Quick access to translations: `context.l10n.nomeChiave`.
extension L10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
