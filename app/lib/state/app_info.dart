/// Build metadata injected at build time via --dart-define (see
/// scripts/build.py). Fallbacks are used when running from source
/// (flutter run, debug builds without the defines).
const String kAppVersion =
    String.fromEnvironment('APP_VERSION', defaultValue: 'dev');
const String kAppBuildTime =
    String.fromEnvironment('APP_BUILD_TIME', defaultValue: 'unknown');
