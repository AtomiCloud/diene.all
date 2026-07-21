import 'package:meta/meta.dart';

/// Fixed app-handoff contract constants (C0 §7). These are NOT schema knobs.
abstract final class AppHandoffConstants {
  /// Opaque nonce TTL — fixed 15 minutes.
  static const Duration nonceTtl = Duration(minutes: 15);

  /// Logto one-time token lifetime — fixed 120 seconds (not a ceiling).
  static const int oneTimeTokenExpiresInSeconds = 120;

  /// Default mount base path; the mount itself is configurable.
  static const String defaultMount = '/app-handoff';
}

/// The engine-owned config block schema (dart-family "engine-owned config block
/// schemas" rule). The `config` lib is the sole merger/validator; this block
/// lives NEXT TO the code that reads it and is composed into the service root
/// schema.
///
/// The OIDC [issuer] is BAKED build-time config and is NEVER doc-sourced
/// (C0 §10/§13) — it is a required key here, and the landscape selector doc
/// parser refuses any `issuer` field so it cannot leak in at runtime.
@immutable
final class AuthEngineConfig {
  const AuthEngineConfig({
    required this.issuer,
    required this.endpoint,
    required this.appId,
    required this.redirectUri,
    required this.scopes,
    this.postLogoutRedirectUri,
    this.appHandoffMount = AppHandoffConstants.defaultMount,
    this.endpointSuffixAllowlist = const <String>['cluster.atomi.cloud'],
  });

  /// Parses and validates the `authEngine` config block (fail-fast on the final
  /// merged layer).
  factory AuthEngineConfig.fromBlock(Map<String, Object?> block) {
    Uri uri(String key, {bool required = true}) {
      final Object? value = block[key];
      if (value == null) {
        if (required) {
          throw FormatException('authEngine.$key is required');
        }
        throw StateError('unreachable');
      }
      if (value is! String || value.isEmpty) {
        throw FormatException('authEngine.$key must be a non-empty URI string');
      }
      final Uri parsed = Uri.parse(value);
      if (!parsed.hasScheme) {
        throw FormatException('authEngine.$key must be an absolute URI', value);
      }
      return parsed;
    }

    String str(String key) {
      final Object? value = block[key];
      if (value is! String || value.isEmpty) {
        throw FormatException('authEngine.$key must be a non-empty string');
      }
      return value;
    }

    final Object? rawScopes = block['scopes'];
    final List<String> scopes = rawScopes is List
        ? rawScopes.map((Object? s) => s.toString()).toList(growable: false)
        : const <String>['openid', 'offline_access'];

    final Object? rawAllow = block['endpointSuffixAllowlist'];
    final List<String> allow = rawAllow is List && rawAllow.isNotEmpty
        ? rawAllow.map((Object? s) => s.toString()).toList(growable: false)
        : const <String>['cluster.atomi.cloud'];

    final Object? mount = block['appHandoffMount'];
    final String mountPath = mount is String && mount.isNotEmpty
        ? mount
        : AppHandoffConstants.defaultMount;
    if (!mountPath.startsWith('/')) {
      throw FormatException('authEngine.appHandoffMount must begin with "/"');
    }

    final Object? postLogout = block['postLogoutRedirectUri'];

    return AuthEngineConfig(
      issuer: uri('issuer'),
      endpoint: uri('endpoint'),
      appId: str('appId'),
      redirectUri: uri('redirectUri'),
      postLogoutRedirectUri: postLogout is String && postLogout.isNotEmpty
          ? Uri.parse(postLogout)
          : null,
      scopes: scopes,
      appHandoffMount: mountPath,
      endpointSuffixAllowlist: allow,
    );
  }

  /// The OIDC issuer — BAKED build-time, never doc-sourced.
  final Uri issuer;

  /// The Logto endpoint.
  final Uri endpoint;

  /// The Logto application id.
  final String appId;

  /// The sign-in redirect URI.
  final Uri redirectUri;

  /// The optional post-logout redirect URI.
  final Uri? postLogoutRedirectUri;

  /// OIDC scopes.
  final List<String> scopes;

  /// The configurable app-handoff mount base (default `/app-handoff`).
  final String appHandoffMount;

  /// Baked endpoint-suffix allowlist enforced on every doc-sourced URL at use
  /// time (C0 §10).
  final List<String> endpointSuffixAllowlist;

  /// The redeem route: `POST {mount}/redeem` (no doubled `app-handoff`).
  String get redeemPath => '$appHandoffMount/redeem';

  /// Whether [url] satisfies the baked endpoint-suffix allowlist. Doc-level
  /// enforcement: a doc containing one bad suffix is untrusted.
  bool allowsUrl(Uri url) {
    final String host = url.host;
    return endpointSuffixAllowlist.any(
      (String suffix) => host == suffix || host.endsWith('.$suffix'),
    );
  }

  /// The declarative block schema the `config` lib composes into the service
  /// root schema. Keys map to a `{type, required}` descriptor.
  static Map<String, Object?> get blockSchema => <String, Object?>{
    r'$id': 'authEngine',
    'type': 'object',
    'required': <String>['issuer', 'endpoint', 'appId', 'redirectUri'],
    'properties': <String, Object?>{
      'issuer': <String, Object?>{'type': 'string', 'format': 'uri'},
      'endpoint': <String, Object?>{'type': 'string', 'format': 'uri'},
      'appId': <String, Object?>{'type': 'string'},
      'redirectUri': <String, Object?>{'type': 'string', 'format': 'uri'},
      'postLogoutRedirectUri': <String, Object?>{
        'type': 'string',
        'format': 'uri',
      },
      'scopes': <String, Object?>{
        'type': 'array',
        'items': <String, Object?>{'type': 'string'},
      },
      'appHandoffMount': <String, Object?>{
        'type': 'string',
        'default': AppHandoffConstants.defaultMount,
      },
      'endpointSuffixAllowlist': <String, Object?>{
        'type': 'array',
        'items': <String, Object?>{'type': 'string'},
      },
    },
  };
}
