/// Normative token lifetimes (C0 §12) — fleet-wide constants, NOT config knobs.
///
/// Any goal citing an access-token TTL must match these values.
abstract final class TokenLifetimes {
  /// Access tokens: 10 minutes.
  static const Duration access = Duration(minutes: 10);

  /// Refresh tokens: 14 days, rotating (reuse detection invalidates family).
  static const Duration refresh = Duration(days: 14);
}
