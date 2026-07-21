import 'config_source.dart';
import 'deep_merge.dart';
import 'overrides.dart';
import 'schema.dart';

/// Loads base YAML, a flavor/landscape overlay, an optional development
/// override, and Dart defines in that order, then validates exactly once.
final class ConfigLoader {
  const ConfigLoader({
    required this.base,
    required this.schema,
    required this.dartDefines,
    this.overlay,
    this.developmentOverride,
  });

  final ConfigSource base;
  final ConfigSource? overlay;
  final ConfigSource? developmentOverride;
  final DartDefineOverrides dartDefines;
  final ConfigSchema schema;

  Future<DieneConfig> load() async {
    Map<String, Object?> merged = await base.load();
    final ConfigSource? selectedOverlay = overlay;
    if (selectedOverlay != null) {
      merged = deepMerge(merged, await selectedOverlay.load());
    }
    final ConfigSource? dev = developmentOverride;
    if (dev != null) {
      merged = deepMerge(merged, await dev.load());
    }
    final Map<String, Object?> configured = dartDefines.apply(merged);
    return schema.validate(configured);
  }
}
