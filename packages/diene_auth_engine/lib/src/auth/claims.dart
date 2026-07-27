import 'dart:convert';

/// Claims-first inspection helpers (C0 §8 S20 + §13).
///
/// The client inspects per-resource JWT claims as the gating truth EVERYWHERE;
/// it never verifies signatures here (that is the provider/JWKS concern) — it
/// only reads the payload to decide onboarding/home routing.
abstract final class Claims {
  /// The `home_landscape` claim name (C0 §13).
  static const String homeLandscape = 'home_landscape';

  /// Decodes the payload segment of a JWT into a claims map. Returns an empty
  /// map for a structurally invalid token (callers treat that as absent).
  static Map<String, Object?> decode(String jwt) {
    final List<String> parts = jwt.split('.');
    if (parts.length < 2) {
      return const <String, Object?>{};
    }
    try {
      final String normalized = base64Url.normalize(parts[1]);
      final Object? decoded = jsonDecode(
        utf8.decode(base64Url.decode(normalized)),
      );
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map(
          (Object? key, Object? value) => MapEntry(key.toString(), value),
        );
      }
      return const <String, Object?>{};
    } on Object {
      return const <String, Object?>{};
    }
  }

  /// Registration claim key (S20): `<platform>_<service>`, both labels
  /// lowercased and every `-` replaced by `_`.
  static String registrationKey({
    required String platform,
    required String service,
  }) {
    String normalize(String label) => label.toLowerCase().replaceAll('-', '_');
    return '${normalize(platform)}_${normalize(service)}';
  }

  /// Whether a decoded [claims] map carries the exact registration claim for
  /// `(platform, service)`. The value MUST be the JSON string `"true"`; a
  /// missing key, null, boolean `true`, or any other value counts as absent.
  static bool hasRegistration(
    Map<String, Object?> claims, {
    required String platform,
    required String service,
  }) {
    final Object? value =
        claims[registrationKey(platform: platform, service: service)];
    return value is String && value == 'true';
  }

  /// The `home_landscape` claim value, or `null` when absent/blank.
  static String? home(Map<String, Object?> claims) {
    final Object? value = claims[homeLandscape];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }
}
