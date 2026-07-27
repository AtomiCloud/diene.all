/// Layered, schema-composed configuration for Dart and Flutter applications.
///
/// The contract in one paragraph: a full **base** YAML document is overlaid by
/// one sparse **flavor/landscape** YAML, then an optional **development**
/// override, then enumerated **`--dart-define`** values LAST; the merged tree is
/// validated exactly once against a schema the SERVICE composes from
/// engine-owned blocks; and the result is immutable for the life of the process.
///
/// ```dart
/// import 'package:diene_config/diene_config.dart';
///
/// final ConfigBlock<ApiSettings> apiBlock = ConfigBlock<ApiSettings>(
///   key: 'api',
///   decode: (Map<String, Object?> values) =>
///       ApiSettings(Uri.parse(values['baseUrl']! as String)),
/// );
///
/// final Result<DieneConfig> loaded = await ConfigLoader(
///   base: YamlConfigSource(name: 'base.yaml', read: readBaseYaml),
///   dartDefines: const DartDefineOverrides(prefix: 'ACME_'),
///   schema: ConfigSchema(blocks: <ConfigBlockSchema>[apiBlock]),
/// ).load();
/// ```
///
/// **What this library owns.** YAML reading, layer orchestration, schema
/// composition and final validation, typed slices, and the landscape accessor.
///
/// **What it does not own.** The merge and environment-key mechanics come from
/// `package:diene_core_utils` (`deepMerge`, `canonicalConfigKey`,
/// `environmentToNestedMap`, `stableConfig`) — there is deliberately no private
/// copy here, because a second implementation of C0 §3 is a second thing to
/// drift. Nor does it own any engine's schema: auth-engine and api-engine
/// export their own [ConfigBlock] values, and the application composes them.
///
/// **Failures are values.** Every expected failure — an unreadable layer, a
/// malformed define key, an invalid final tree, a missing landscape — is an
/// `Err` carrying the RFC 9457 `Problem` envelope from `package:diene_problems`.
/// Throwing is reserved for programmer misuse (a duplicate block key, a slice
/// that was never composed).
library;

export 'c0_config.dart';
export 'src/config_loader.dart';
export 'src/config_problem.dart';
export 'src/config_source.dart';
export 'src/landscape.dart';
export 'src/schema.dart';
