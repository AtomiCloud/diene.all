import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// The four-slot LPSM service-tree coordinate that addresses one backend.
/// Instance is a projection parameter elsewhere in the fleet and is NOT part
/// of this coordinate.
@immutable
class LpsmCoordinate {
  const LpsmCoordinate({
    required this.landscape,
    required this.platform,
    required this.service,
    required this.module,
  });

  factory LpsmCoordinate.fromMap(Map<String, Object?> value) => LpsmCoordinate(
        landscape: _string(value, 'landscape'),
        platform: _string(value, 'platform'),
        service: _string(value, 'service'),
        module: _string(value, 'module'),
      );

  final String landscape;
  final String platform;
  final String service;
  final String module;

  /// Stable registry key.
  String get key => '$landscape.$platform.$service.$module';

  Map<String, Object?> toMap() => <String, Object?>{
        'landscape': landscape,
        'platform': platform,
        'service': service,
        'module': module,
      };

  @override
  bool operator ==(Object other) => other is LpsmCoordinate && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => key;
}

/// One backend registration. The base URL is EXACTLY ONE hostname — the home
/// landscape's, sourced from config values (never a literal, never a physical
/// per-cluster URL list). `authResource` names the per-resource token the
/// `IAuth` seam resolves for this backend (multi-backend: no shared token).
@immutable
class BackendConfig {
  const BackendConfig({
    required this.coordinate,
    required this.baseUrl,
    this.authResource,
    this.timeout = const Duration(seconds: 30),
    this.retryOnNetworkError = true,
  });

  factory BackendConfig.fromMap(Map<String, Object?> value) => BackendConfig(
        coordinate: LpsmCoordinate.fromMap(_map(value, 'coordinate')),
        baseUrl: Uri.parse(_string(value, 'baseUrl')),
        authResource: value['authResource'] as String?,
        timeout: Duration(
          seconds: (value['timeoutSeconds'] as num?)?.toInt() ?? 30,
        ),
        retryOnNetworkError: value['retryOnNetworkError'] as bool? ?? true,
      );

  final LpsmCoordinate coordinate;
  final Uri baseUrl;
  final String? authResource;
  final Duration timeout;
  final bool retryOnNetworkError;
}

/// Baked rescue configuration for the dormant router. Everything here is
/// build-time baked: the router NEVER learns its issuer or its allowed URL
/// suffixes from a doc.
@immutable
class RescueConfig {
  const RescueConfig({
    required this.enabled,
    required this.issuer,
    required this.catalogHosts,
    required this.endpointSuffixAllowlist,
    this.scanBudget = const Duration(seconds: 8),
    this.perCandidateTimeout = const Duration(seconds: 3),
    this.maxJitter = const Duration(milliseconds: 250),
  });

  factory RescueConfig.fromMap(Map<String, Object?> value) => RescueConfig(
        // Enabled is a PER-CONTEXT flag: ON for Flutter/browser, OFF for the
        // nextjs server runtime (whose rescue is redeploy).
        enabled: value['enabled'] as bool? ?? false,
        issuer: Uri.parse(_string(value, 'issuer')),
        catalogHosts: _stringList(value, 'catalogHosts'),
        endpointSuffixAllowlist: _stringList(value, 'endpointSuffixAllowlist'),
        scanBudget: Duration(
          milliseconds: (value['scanBudgetMs'] as num?)?.toInt() ?? 8000,
        ),
        perCandidateTimeout: Duration(
          milliseconds:
              (value['perCandidateTimeoutMs'] as num?)?.toInt() ?? 3000,
        ),
        maxJitter: Duration(
          milliseconds: (value['maxJitterMs'] as num?)?.toInt() ?? 250,
        ),
      );

  /// Per-context enable flag. When false the router stays fully dormant and a
  /// hard failure surfaces the transport-failure Problem directly.
  final bool enabled;

  /// The auth issuer — ALWAYS baked, never doc-sourced.
  final Uri issuer;

  /// Doc A seed: the baked `catalogHosts[]` spanning failure domains (R2 via
  /// CF custom domain, CloudFront via the R53 rescue domain, cloudfront.net).
  final List<String> catalogHosts;

  /// Baked endpoint-suffix allowlist enforced on every doc-sourced URL at USE
  /// time (only our own baked roots, e.g. `.cluster.atomi.cloud` + rescue
  /// root(s)). A poisoned doc can at worst cross-wire within our own hosts.
  final List<String> endpointSuffixAllowlist;

  final Duration scanBudget;
  final Duration perCandidateTimeout;
  final Duration maxJitter;
}

/// The engine-owned config block schema (dart family has no standard-config
/// member; each engine owns its own block beside the code that reads it). The
/// CONFIG lib merges/validates this block into the service-composed root and
/// serves a typed slice; it never owns this schema.
@immutable
class ApiEngineConfig {
  const ApiEngineConfig({required this.backends, required this.rescue});

  /// Parses (and validates) an already-merged config slice. Throws
  /// [FormatException] on an invalid slice (fail-fast on the final layer, per
  /// the config contract).
  factory ApiEngineConfig.fromMap(Map<String, Object?> value) {
    final List<Object?> raw = _list(value, 'backends');
    final List<BackendConfig> backends = raw
        .map(
          (Object? item) => BackendConfig.fromMap(
            _asMap(item, 'backends[]'),
          ),
        )
        .toList(growable: false);
    if (backends.isEmpty) {
      throw const FormatException('api-engine config needs ≥1 backend');
    }
    final Set<String> keys = <String>{};
    for (final BackendConfig backend in backends) {
      if (!keys.add(backend.coordinate.key)) {
        throw FormatException(
          'duplicate backend registration: ${backend.coordinate.key}',
        );
      }
    }
    return ApiEngineConfig(
      backends: backends,
      rescue: RescueConfig.fromMap(_map(value, 'rescue')),
    );
  }

  final List<BackendConfig> backends;
  final RescueConfig rescue;

  /// A machine-readable description of this engine block, exported so the
  /// config lib can compose it into the root schema. Deliberately a plain
  /// map (JSON-schema-shaped) so no schema library is pulled in.
  static Map<String, Object?> get schema => <String, Object?>{
        r'$id': 'urn:diene:config-block:api-engine',
        'type': 'object',
        'required': <String>['backends', 'rescue'],
        'properties': <String, Object?>{
          'backends': <String, Object?>{
            'type': 'array',
            'minItems': 1,
            'items': <String, Object?>{
              'type': 'object',
              'required': <String>['coordinate', 'baseUrl'],
              'properties': <String, Object?>{
                'coordinate': <String, Object?>{
                  'type': 'object',
                  'required': <String>[
                    'landscape',
                    'platform',
                    'service',
                    'module',
                  ],
                },
                'baseUrl': <String, Object?>{'type': 'string', 'format': 'uri'},
                'authResource': <String, Object?>{'type': 'string'},
                'timeoutSeconds': <String, Object?>{'type': 'integer'},
                'retryOnNetworkError': <String, Object?>{'type': 'boolean'},
              },
            },
          },
          'rescue': <String, Object?>{
            'type': 'object',
            'required': <String>[
              'enabled',
              'issuer',
              'catalogHosts',
              'endpointSuffixAllowlist',
            ],
            'properties': <String, Object?>{
              'enabled': <String, Object?>{'type': 'boolean'},
              'issuer': <String, Object?>{'type': 'string', 'format': 'uri'},
              'catalogHosts': <String, Object?>{
                'type': 'array',
                'items': <String, Object?>{'type': 'string'},
              },
              'endpointSuffixAllowlist': <String, Object?>{
                'type': 'array',
                'items': <String, Object?>{'type': 'string'},
              },
              'scanBudgetMs': <String, Object?>{'type': 'integer'},
              'perCandidateTimeoutMs': <String, Object?>{'type': 'integer'},
              'maxJitterMs': <String, Object?>{'type': 'integer'},
            },
          },
        },
      };

  static const DeepCollectionEquality _eq = DeepCollectionEquality();

  /// True when [schema] equals a previously-frozen copy — used by the C0
  /// conformance test to catch accidental schema drift.
  static bool schemaEquals(Map<String, Object?> other) =>
      _eq.equals(schema, other);
}

// --- typed accessors (fail-fast) -------------------------------------------

Map<String, Object?> _map(Map<String, Object?> value, String key) =>
    _asMap(value[key], key);

Map<String, Object?> _asMap(Object? item, String label) {
  if (item is! Map) {
    throw FormatException('config key $label must be a map');
  }
  return item.map(
    (Object? k, Object? v) => MapEntry(k.toString(), v),
  );
}

List<Object?> _list(Map<String, Object?> value, String key) {
  final Object? item = value[key];
  if (item is! List) {
    throw FormatException('config key $key must be a list');
  }
  return item;
}

List<String> _stringList(Map<String, Object?> value, String key) =>
    _list(value, key).map((Object? item) => item.toString()).toList(
          growable: false,
        );

String _string(Map<String, Object?> value, String key) {
  final Object? item = value[key];
  if (item is! String || item.isEmpty) {
    throw FormatException('config key $key must be a non-empty string');
  }
  return item;
}
