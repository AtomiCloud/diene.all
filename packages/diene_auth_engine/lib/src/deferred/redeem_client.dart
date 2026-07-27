import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

/// Telemetry-only device info sent on redeem (C0 §7). It MUST NOT affect
/// identity or authorization.
final class DeviceInfo {
  const DeviceInfo({
    required this.platform,
    this.appVersion,
    this.osVersion,
    this.model,
  });

  /// `android` or `ios`.
  final String platform;
  final String? appVersion;
  final String? osVersion;
  final String? model;

  Map<String, Object?> toJson() => <String, Object?>{
    'platform': platform,
    if (appVersion != null) 'appVersion': appVersion,
    if (osVersion != null) 'osVersion': osVersion,
    if (model != null) 'model': model,
  };
}

/// The successful redeem payload: a Logto one-time token (`expiresIn` fixed at
/// 120s) plus the resolved primary email.
final class RedeemResult {
  const RedeemResult({
    required this.token,
    required this.email,
    this.expiresIn = 120,
  });

  final String token;
  final String email;
  final int expiresIn;
}

/// The single no-oracle redeem failure (C0 §7): `AppHandoffExpired`, 410. Every
/// failure — missing, expired, replayed, deleted, suspended, rebound, upstream
/// — returns exactly this. No account-state oracle.
Problem appHandoffExpired() => const Problem(
  type: 'urn:diene:problem:app-handoff-expired',
  title: 'App handoff expired',
  status: 410,
  detail: 'This app handoff is expired or invalid.',
);

/// The redeem HTTP surface against `POST {mount}/redeem`. Implementations do
/// the transport; every failure maps to [appHandoffExpired].
abstract interface class AppHandoffApi {
  /// Redeems [nonce] with telemetry-only [device]. Returns the minted one-time
  /// token on success, or the generic-expiry [Problem] otherwise.
  Future<Result<RedeemResult>> redeem({
    required String nonce,
    required DeviceInfo device,
  });
}
