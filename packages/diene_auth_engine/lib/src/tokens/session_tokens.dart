import 'package:meta/meta.dart';

import 'resource_key.dart';

/// The refresh/access pair for one authenticated Logto session.
///
/// `refreshFamily` identifies the rotating refresh-token family; a refresh that
/// returns a different family (or re-returns the same refresh token) is treated
/// as reuse/theft by the session controller (C0 §12).
@immutable
final class SessionTokens {
  const SessionTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.refreshFamily,
    required this.accessExpiresAt,
    required this.refreshExpiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final String refreshFamily;
  final DateTime accessExpiresAt;
  final DateTime refreshExpiresAt;

  /// Whether the access token is still valid at [now].
  bool accessValidAt(DateTime now) => accessExpiresAt.isAfter(now.toUtc());

  /// Whether the refresh token is still valid at [now].
  bool refreshValidAt(DateTime now) => refreshExpiresAt.isAfter(now.toUtc());

  @override
  bool operator ==(Object other) =>
      other is SessionTokens &&
      other.accessToken == accessToken &&
      other.refreshToken == refreshToken &&
      other.refreshFamily == refreshFamily &&
      other.accessExpiresAt == accessExpiresAt &&
      other.refreshExpiresAt == refreshExpiresAt;

  @override
  int get hashCode => Object.hash(
    accessToken,
    refreshToken,
    refreshFamily,
    accessExpiresAt,
    refreshExpiresAt,
  );
}

/// A single per-resource access token acquired through the IAuth seam.
@immutable
final class ResourceToken {
  const ResourceToken({required this.token, required this.expiresAt});

  final String token;
  final DateTime expiresAt;

  /// Whether this token is still valid at [now].
  bool validAt(DateTime now) => expiresAt.isAfter(now.toUtc());

  @override
  bool operator ==(Object other) =>
      other is ResourceToken &&
      other.token == token &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(token, expiresAt);
}

/// The terminal result of acquiring one [ResourceKey]'s token in a batch.
@immutable
final class ResourceTokenEntry {
  const ResourceTokenEntry({required this.key, required this.token});

  final ResourceKey key;
  final ResourceToken token;
}
