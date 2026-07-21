/// Supplies the build-time landscape identity.
abstract interface class LandscapeSource {
  String read();
}

/// Reads the mobile store track from `--dart-define=DIENE_LANDSCAPE=...`.
///
/// This is an accessor, not a detector. It never examines hostnames or runtime
/// environment state.
final class DartDefineLandscapeSource implements LandscapeSource {
  const DartDefineLandscapeSource({
    this.value = const String.fromEnvironment('DIENE_LANDSCAPE'),
  });

  final String value;

  @override
  String read() => value;
}

/// Returns the build-time landscape identity.
String landscape({LandscapeSource source = const DartDefineLandscapeSource()}) {
  final String value = source.read().trim();
  if (value.isEmpty) {
    throw StateError(
      'Landscape is missing; pass --dart-define=DIENE_LANDSCAPE=<track>',
    );
  }
  return value;
}
