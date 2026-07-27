import '../contracts/problem.dart';
import '../contracts/result.dart';

/// One landscape entry in Doc B — the landscape selector (C0 §10).
///
/// NAMES + metadata ONLY — no addresses, no issuer. The client derives ping
/// URLs by convention from [name]; it never reads a URL out of the doc.
final class LandscapeEntry {
  const LandscapeEntry({
    required this.name,
    required this.region,
    this.metadata = const <String, Object?>{},
  });

  final String name;
  final String region;
  final Map<String, Object?> metadata;
}

/// Doc B — the landscape selector doc (per platform × env).
///
/// `{ platform, tier, landscapes: [{ name, region, metadata… }, …] }`. A
/// health-gated entry appears ONLY once its deployment is healthy.
final class LandscapeSelectorDoc {
  const LandscapeSelectorDoc({
    required this.platform,
    required this.tier,
    required this.landscapes,
  });

  /// Parses Doc B, RECURSIVELY rejecting any entry that leaks an
  /// address/issuer/URL — as a key name anywhere (including nested `metadata`)
  /// or as a URL-shaped string value. A doc containing one leak is untrusted.
  factory LandscapeSelectorDoc.fromJson(Map<String, Object?> json) {
    final Object? rawList = json['landscapes'];
    if (rawList is! List) {
      throw const FormatException('Doc B must carry a landscapes list');
    }
    final List<LandscapeEntry> entries = <LandscapeEntry>[];
    for (final Object? item in rawList) {
      if (item is! Map) {
        throw const FormatException('Doc B landscape entry must be a map');
      }
      final Map<String, Object?> entry = item.map(
        (Object? key, Object? value) => MapEntry(key.toString(), value),
      );
      // Reject prohibited identity/address/URL material at ANY depth.
      _assertNoProhibited(entry);

      final Object? name = entry['name'];
      final Object? region = entry['region'];
      if (name is! String || name.isEmpty || region is! String) {
        throw const FormatException('Doc B entry needs a name and region');
      }
      entries.add(
        LandscapeEntry(
          name: name,
          region: region,
          metadata:
              (entry['metadata'] as Map<Object?, Object?>? ??
                      const <Object?, Object?>{})
                  .map(
                    (Object? key, Object? value) =>
                        MapEntry(key.toString(), value),
                  ),
        ),
      );
    }
    return LandscapeSelectorDoc(
      platform: json['platform']?.toString() ?? '',
      tier: json['tier']?.toString() ?? '',
      landscapes: entries,
    );
  }

  /// Prohibited identity/address/issuer key names (case-insensitive). Doc B
  /// carries landscape NAMES + metadata ONLY (C0 §10).
  static const Set<String> _forbiddenKeys = <String>{
    'address',
    'addresses',
    'host',
    'hosts',
    'hostname',
    'url',
    'uri',
    'href',
    'endpoint',
    'endpoints',
    'issuer',
    'authority',
    'origin',
    'ip',
    'ipaddress',
  };

  /// Recursively walks maps/lists rejecting any prohibited key name or any
  /// URL-shaped string value (a `scheme://`, `http(s):`, or `//host` form).
  static void _assertNoProhibited(Object? node) {
    if (node is Map) {
      node.forEach((Object? key, Object? value) {
        if (_forbiddenKeys.contains(key.toString().toLowerCase())) {
          throw FormatException(
            'Doc B must not carry addresses/issuer/URLs',
            key.toString(),
          );
        }
        _assertNoProhibited(value);
      });
    } else if (node is List) {
      for (final Object? element in node) {
        _assertNoProhibited(element);
      }
    } else if (node is String && _looksLikeUrl(node)) {
      throw FormatException('Doc B must not carry a URL/address value', node);
    }
  }

  static bool _looksLikeUrl(String value) {
    final String v = value.trim().toLowerCase();
    if (v.startsWith('//') || v.contains('://')) {
      return true;
    }
    return v.startsWith('http:') || v.startsWith('https:');
  }

  final String platform;
  final String tier;
  final List<LandscapeEntry> landscapes;
}

/// Fetches Doc B. The fetch URL itself is endpoint-suffix-allowlisted by the
/// implementation (C0 §10); the parsed doc carries no URLs.
abstract interface class LandscapeSelectorSource {
  Future<LandscapeSelectorDoc> fetch();
}

/// Pings one region and returns its round-trip latency, or `null` when the
/// region is unreachable/unhealthy. Ping URLs are derived by convention from
/// the landscape name (never doc-carried).
abstract interface class RegionPinger {
  Future<Duration?> ping(LandscapeEntry entry);
}

/// Client twin of the bun-frontend-utils edge-doc client, SIGN-UP ONLY.
///
/// Fetches Doc B → pings each listed region → picks the fastest healthy one (or
/// honours a caller [preferred] name when it is healthy). Used ONCE, at sign-up;
/// never a per-request routing layer.
final class LandscapeSelectorClient {
  const LandscapeSelectorClient({required this._source, required this._pinger});

  final LandscapeSelectorSource _source;
  final RegionPinger _pinger;

  /// Selects the home landscape. Returns the chosen landscape name.
  Future<Result<String>> selectHome({String? preferred}) async {
    final LandscapeSelectorDoc doc;
    try {
      doc = await _source.fetch();
    } on Object catch (error) {
      return Failure<String>(
        Problem(
          type: 'urn:diene:problem:landscape-doc',
          title: 'Could not fetch the landscape selector',
          status: 503,
          detail: error.toString(),
          recoverable: true,
        ),
      );
    }
    if (doc.landscapes.isEmpty) {
      return const Failure<String>(
        Problem(
          type: 'urn:diene:problem:landscape-empty',
          title: 'No landscapes offered',
          status: 503,
          recoverable: true,
        ),
      );
    }

    // Ping every region; keep only healthy ones with their latency.
    final Map<String, Duration> healthy = <String, Duration>{};
    await Future.wait(<Future<void>>[
      for (final LandscapeEntry entry in doc.landscapes)
        _pinger.ping(entry).then((Duration? latency) {
          if (latency != null) {
            healthy[entry.name] = latency;
          }
        }),
    ]);

    if (healthy.isEmpty) {
      return const Failure<String>(
        Problem(
          type: 'urn:diene:problem:landscape-unhealthy',
          title: 'No healthy landscape found',
          status: 503,
          recoverable: true,
        ),
      );
    }

    // Honour an explicit healthy preference; otherwise pick the fastest.
    if (preferred != null && healthy.containsKey(preferred)) {
      return Success<String>(preferred);
    }
    final MapEntry<String, Duration> fastest = healthy.entries.reduce(
      (MapEntry<String, Duration> a, MapEntry<String, Duration> b) =>
          a.value <= b.value ? a : b,
    );
    return Success<String>(fastest.key);
  }
}
