/// Compatibility entrypoint for apps migrating off an in-app
/// `lib/config/app_config.dart`.
///
/// The neon seed app carried its own `lib/config/app_config.dart` holding a
/// hand-rolled `AppConfig` singleton. Deleting that file is the point of this
/// package — but a migrating app has `import 'config/app_config.dart';` and an
/// `AppConfig.instance.…` call at dozens of call sites, and changing all of
/// them in the same commit that swaps the implementation makes the swap
/// impossible to review.
///
/// So this entrypoint exists to be imported INSTEAD, at the same path shape:
///
/// ```dart
/// // was: import 'config/app_config.dart';
/// import 'package:diene_config/config/app_config.dart';
/// ```
///
/// It re-exports the whole public surface and adds [AppConfig] — a one-shot
/// holder giving the seed's `AppConfig.instance` idiom somewhere to land while
/// call sites move to passing [DieneConfig] explicitly.
///
/// **This is a migration aid, not the recommended surface.** Ambient global
/// state is exactly what the rest of this package avoids: a loader you can
/// construct twice, a config value you can pass into a widget or a test. New
/// code imports `package:diene_config/diene_config.dart` and threads
/// [DieneConfig] through constructors. A migrated app is finished when nothing
/// imports this file.
library;

import 'package:diene_result/diene_result.dart';

import '../diene_config.dart';

export '../diene_config.dart';

/// A process-wide holder for the loaded configuration.
///
/// Deliberately minimal: install once at startup, read anywhere, reset in
/// tests. It adds no merge, validation, or loading behaviour of its own — it
/// only remembers the [DieneConfig] that [ConfigLoader] produced.
abstract final class AppConfig {
  static DieneConfig? _instance;

  /// Whether a configuration has been installed.
  static bool get isInstalled => _instance != null;

  /// The installed configuration.
  ///
  /// Throws [StateError] before [install] is called. Reading configuration
  /// before it is loaded is a startup-ordering BUG, not a runtime condition to
  /// branch on, so it throws rather than returning a failure value — and it
  /// throws loudly instead of handing back a silent default that would let the
  /// app run against configuration nobody supplied.
  static DieneConfig get instance {
    final DieneConfig? installed = _instance;
    if (installed == null) {
      throw StateError(
        'AppConfig.instance was read before install(); call '
        'AppConfig.install(config) once during startup.',
      );
    }
    return installed;
  }

  /// The installed configuration as an [Option], for callers that legitimately
  /// run before startup completes.
  static Option<DieneConfig> get maybeInstance =>
      Option<DieneConfig>.fromNullable(_instance);

  /// Installs [config] as the process-wide configuration.
  ///
  /// Throws [StateError] on a second install unless [force] is set. A silent
  /// second install would mean two parts of the app disagree about what the
  /// configuration is, and the loser would be whichever ran first.
  static void install(DieneConfig config, {bool force = false}) {
    if (_instance != null && !force) {
      throw StateError(
        'AppConfig is already installed; pass force: true to replace it.',
      );
    }
    _instance = config;
  }

  /// Loads through [loader] and installs the result on success.
  ///
  /// The failure channel is unchanged: an `Err` is returned and NOTHING is
  /// installed, so a failed load cannot leave a half-configured process.
  static Future<Result<DieneConfig>> loadAndInstall(
    ConfigLoader loader, {
    bool force = false,
  }) async {
    final Result<DieneConfig> loaded = await loader.load();
    return loaded.run((DieneConfig config) => install(config, force: force));
  }

  /// Clears the installed configuration.
  ///
  /// For test teardown and for an app that genuinely tears down its own
  /// startup. Production code should not need this.
  static void reset() {
    _instance = null;
  }
}
