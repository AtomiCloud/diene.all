/// Normative token lifetimes (C0 §12) — fleet-wide constants, NOT config knobs.
///
/// Any goal citing an access-token TTL must match these values. All four
/// members mirror `contracts/c0/cases/identity.json` → `cases.tokenLifetimes`
/// exactly (`accessMinutes`, `refreshDays`, `refreshRotating`, `remintOnOpen`);
/// the C0 conformance suite asserts each one against that fixture, so a drift
/// here turns the conformance tier red rather than silently shipping.
abstract final class TokenLifetimes {
  /// Access tokens: 10 minutes (`accessMinutes: 10`).
  static const Duration access = Duration(minutes: 10);

  /// Refresh tokens: 14 days (`refreshDays: 14`).
  static const Duration refresh = Duration(days: 14);

  /// Refresh tokens ROTATE on every use (`refreshRotating: true`).
  ///
  /// Rotation is what makes reuse detection possible: presenting an already
  /// exchanged refresh token invalidates the whole token family rather than
  /// issuing a fresh pair. The engine never treats a refresh token as
  /// replayable.
  static const bool refreshRotating = true;

  /// The app re-mints on open (`remintOnOpen: true`) rather than trusting a
  /// cached access token for its remaining TTL.
  static const bool remintOnOpen = true;
}
