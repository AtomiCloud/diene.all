/// E4-final integration barrel.
///
/// Aggregates the E4-final integration scaffold: the integration manifest (what
/// is wired vs. held) and the observability wiring that stands live on
/// flutter-base + the observability payload. The held diene package surface
/// (from `lib/dart/e2e`) is intentionally NOT exported here yet — it is added by
/// the T13-REBASE pass once e2e obtains an accepted sha.
library;

export 'e4_manifest.dart';
export 'observability_wiring.dart';
