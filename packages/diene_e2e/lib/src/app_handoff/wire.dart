/// Deferred-login (app-handoff) JSON/HTTP v1 wire models — C0 §7.
///
/// Pure value types for the mint and redeem exchanges plus the single
/// no-oracle `AppHandoffExpired` problem. These model the wire contract only;
/// they hold no server logic. The shared fixture and consumer journeys build
/// and parse these instead of hand-authoring JSON.
library;

/// Default mount base path for the app-handoff module (C0 §7). The mint route
/// is `POST {mount}` and the redeem route is `POST {mount}/redeem`.
const String appHandoffDefaultMount = '/app-handoff';

/// The redeem sub-path appended to the configured mount (C0 §7).
const String appHandoffRedeemPath = 'redeem';

/// Successful mint response body: `{ "nonce", "expiresAt" }` (C0 §7).
///
/// [expiresAt] is an RFC 3339 UTC instant string carried verbatim — the codec
/// does not reformat it, so a consumer round-trips exactly what the server
/// sent.
class AppHandoffMint {
  const AppHandoffMint({required this.nonce, required this.expiresAt});

  factory AppHandoffMint.fromJson(Map<String, Object?> json) => AppHandoffMint(
    nonce: json['nonce']! as String,
    expiresAt: json['expiresAt']! as String,
  );

  final String nonce;
  final String expiresAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'nonce': nonce,
    'expiresAt': expiresAt,
  };
}

/// Telemetry-only device descriptor on a redeem request (C0 §7). Per contract
/// this MUST NOT affect identity or authorization.
class AppHandoffDevice {
  const AppHandoffDevice({
    required this.platform,
    this.appVersion,
    this.osVersion,
    this.model,
  });

  factory AppHandoffDevice.fromJson(Map<String, Object?> json) =>
      AppHandoffDevice(
        platform: json['platform']! as String,
        appVersion: json['appVersion'] as String?,
        osVersion: json['osVersion'] as String?,
        model: json['model'] as String?,
      );

  /// `android` or `ios` (C0 §7).
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

/// Redeem request body `{ "nonce", "device" }` (C0 §7).
class AppHandoffRedeemRequest {
  const AppHandoffRedeemRequest({required this.nonce, required this.device});

  factory AppHandoffRedeemRequest.fromJson(Map<String, Object?> json) =>
      AppHandoffRedeemRequest(
        nonce: json['nonce']! as String,
        device: AppHandoffDevice.fromJson(
          json['device']! as Map<String, Object?>,
        ),
      );

  final String nonce;
  final AppHandoffDevice device;

  Map<String, Object?> toJson() => <String, Object?>{
    'nonce': nonce,
    'device': device.toJson(),
  };
}

/// Successful redeem response `{ "token", "email", "expiresIn" }` (C0 §7).
///
/// [expiresIn] is fixed at 120 seconds by the contract, exposed as a constant
/// so fixtures cannot drift from it.
class AppHandoffRedeemResponse {
  const AppHandoffRedeemResponse({
    required this.token,
    required this.email,
    this.expiresIn = appHandoffTokenExpiresInSeconds,
  });

  factory AppHandoffRedeemResponse.fromJson(Map<String, Object?> json) =>
      AppHandoffRedeemResponse(
        token: json['token']! as String,
        email: json['email']! as String,
        expiresIn: json['expiresIn'] as int? ?? appHandoffTokenExpiresInSeconds,
      );

  final String token;
  final String email;
  final int expiresIn;

  Map<String, Object?> toJson() => <String, Object?>{
    'token': token,
    'email': email,
    'expiresIn': expiresIn,
  };
}

/// Fixed one-time-token lifetime for a redeemed handoff, in seconds (C0 §7).
const int appHandoffTokenExpiresInSeconds = 120;

/// The single no-oracle redeem failure (C0 §7): RFC 9457 problem id
/// `AppHandoffExpired`, status `410`. Every redeem failure — missing, expired,
/// replayed, deleted, suspended, rebound, or upstream — returns exactly this
/// body, so it exposes no account-state oracle.
class AppHandoffExpired {
  const AppHandoffExpired({required this.type});

  /// Builds the problem for a service whose problem-type URIs are rooted at
  /// [typeUri] for the `AppHandoffExpired` id. The `type` URI is produced by
  /// C0 §2 in the owning service; the fixture accepts it as an opaque input so
  /// this package never re-implements the §2 URI builder.
  factory AppHandoffExpired.withType(String typeUri) =>
      AppHandoffExpired(type: typeUri);

  static const String problemId = 'AppHandoffExpired';
  static const int status = 410;
  static const String title = 'App handoff expired';
  static const String detail = 'This app handoff is expired or invalid.';

  /// The `type` URI, built by C0 §2 in the owning service.
  final String type;

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'title': title,
    'status': status,
    'detail': detail,
    'data': const <String, Object?>{},
  };
}
