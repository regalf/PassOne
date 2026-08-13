import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'session.dart';
import 'settings.dart';

final settingsRepositoryProvider =
    Provider<SettingsRepository>((ref) => SettingsRepository());

final sessionControllerProvider =
    StateNotifierProvider<SessionController, SessionState>(
  (ref) => SessionController(ref.read(settingsRepositoryProvider)),
);
