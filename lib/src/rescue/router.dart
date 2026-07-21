import 'dart:convert';

import '../config.dart';
import '../transport.dart';
import 'docs.dart';
import 'store.dart';

/// Result of a rescue attempt. [Rescued] carries an allowlisted base URL to
/// pin and use; [RescueUnavailable] means the router could not rescue (caller
/// surfaces the original transport-failure Problem).
sealed class RescueOutcome {
  const RescueOutcome();
}

final class Rescued extends RescueOutcome {
  const Rescued(this.baseUrl, {required this.fromLastKnownGood});

  final Uri baseUrl;
  final bool fromLastKnownGood;
}

final class RescueUnavailable extends RescueOutcome {
  const RescueUnavailable(this.reason);

  final String reason;
}

/// The DORMANT rescue router (dart twin of the shared bun api-engine/
/// frontend-utils machinery; dart has no frontend-utils lib so the router
/// lives here). It only ever runs after a hard connect-failure past
/// retry-once, and only when [RescueConfig.enabled] is true for the context.
///
/// It rescues ADDRESSES only, same landscape, never cross-landscape. Safety
/// rails: a baked endpoint-suffix allowlist enforced on EVERY doc-sourced URL
/// at use time; monotonic doc versions (never accept older than seen); an
/// always-baked issuer (never doc-sourced); last-known-good kept forever; no
/// doc signing.
class RescueRouter {
  RescueRouter({
    required this.config,
    required this.store,
    required this.transport,
    Future<void> Function(Duration duration)? sleep,
    int Function()? nowMs,
    Duration Function()? jitter,
  })  : _sleep = sleep ?? Future<void>.delayed,
        _nowMs = nowMs ?? _wallClockMs,
        _jitter = jitter ?? (() => Duration.zero);

  final RescueConfig config;
  final RescueStore store;
  final HttpTransport transport;
  final Future<void> Function(Duration duration) _sleep;
  final int Function() _nowMs;
  final Duration Function() _jitter;

  static int _wallClockMs() => DateTime.now().millisecondsSinceEpoch;

  static const String _docCKey = 'docc';
  static const String _docCVersionKey = 'docc.version';
  static const String _docAVersionKey = 'doca.version';
  String _pinKey(LpsmCoordinate c) => 'pin.${c.key}';
  String _lastGoodKey(LpsmCoordinate c) => 'lastgood.${c.key}';

  /// The always-baked issuer. Exposed so callers can assert they never read it
  /// from a doc.
  Uri get bakedIssuer => config.issuer;

  /// Enforce the baked endpoint-suffix allowlist on a doc-sourced URL.
  bool isAllowed(Uri url) {
    final String host = url.host;
    if (host.isEmpty) {
      return false;
    }
    return config.endpointSuffixAllowlist.any(
      (String suffix) => host == suffix || host.endsWith(suffix),
    );
  }

  /// The currently-pinned rescue address for [coordinate], if any and still
  /// allowlisted. Used for pin-until-primary-heals: while a pin exists,
  /// requests skip the (broken) primary and go here.
  Future<Uri?> pinnedFor(LpsmCoordinate coordinate) async {
    final String? raw = await store.read(_pinKey(coordinate));
    if (raw == null) {
      return null;
    }
    final Uri url = Uri.parse(raw);
    return isAllowed(url) ? url : null;
  }

  /// Clear the pin once the primary home root heals (pin-until-primary-heals).
  Future<void> onPrimaryHealed(LpsmCoordinate coordinate) =>
      store.delete(_pinKey(coordinate));

  /// Probe whether the primary base URL is reachable again.
  Future<bool> probeHealthy(Uri baseUrl) async {
    final TransportOutcome outcome = await transport.send(
      HttpRequest(method: HttpMethod.head, url: baseUrl),
    );
    return outcome is Received && outcome.response.status < 500;
  }

  /// The full rescue flow for [coordinate].
  Future<RescueOutcome> rescue(LpsmCoordinate coordinate) async {
    if (!config.enabled) {
      return const RescueUnavailable('rescue disabled for this context');
    }

    final DocC? docC = await _loadOrRefreshDocC(coordinate);
    final Uri? lastGood = await _lastKnownGood(coordinate);

    final List<Uri> candidates = <Uri>[
      if (docC != null)
        ...?docC.candidates[coordinate.key]
            ?.map(Uri.parse)
            .where(isAllowed), // allowlist enforced at USE time
    ];

    final int start = _nowMs();
    for (final Uri candidate in candidates) {
      if (_nowMs() - start > config.scanBudget.inMilliseconds) {
        break; // budget exhausted
      }
      await _sleep(_jitter());
      if (await probeHealthy(candidate)) {
        await _pin(coordinate, candidate);
        return Rescued(candidate, fromLastKnownGood: false);
      }
    }

    // No fresh candidate healthy within budget — fall back to last-known-good,
    // which is kept forever and still allowlisted.
    if (lastGood != null && isAllowed(lastGood)) {
      return Rescued(lastGood, fromLastKnownGood: true);
    }
    return const RescueUnavailable(
        'no healthy candidate and no last-known-good');
  }

  Future<Uri?> _lastKnownGood(LpsmCoordinate coordinate) async {
    final String? raw = await store.read(_lastGoodKey(coordinate));
    return raw == null ? null : Uri.parse(raw);
  }

  Future<void> _pin(LpsmCoordinate coordinate, Uri url) async {
    await store.write(_pinKey(coordinate), url.toString());
    await store.write(_lastGoodKey(coordinate), url.toString());
  }

  /// Load Doc C from disk (cached forever) and opportunistically refresh it
  /// via Doc A's baked catalog hosts, honouring monotonic versions.
  Future<DocC?> _loadOrRefreshDocC(LpsmCoordinate coordinate) async {
    DocC? cached;
    final String? cachedRaw = await store.read(_docCKey);
    if (cachedRaw != null) {
      cached = DocC.tryDecode(cachedRaw);
    }
    final int? seenDocC = _parseInt(await store.read(_docCVersionKey));

    // Refresh path: Doc A → Doc C, from baked hosts. Any fetch failure leaves
    // the cached copy in place (Primordial down ⇒ docs freeze at last state).
    final DocA? docA = await _fetchDocA();
    if (docA != null) {
      final int? seenDocA = _parseInt(await store.read(_docAVersionKey));
      if (_isNewer(docA.version, seenDocA)) {
        await store.write(_docAVersionKey, docA.version.toString());
        final DocC? fetched = await _fetchDocC(docA, coordinate);
        if (fetched != null && _isNewer(fetched.version, seenDocC)) {
          await store.write(_docCKey, fetched.encode());
          await store.write(_docCVersionKey, fetched.version.toString());
          return fetched;
        }
      }
    }
    return cached;
  }

  Future<DocA?> _fetchDocA() async {
    for (final String host in config.catalogHosts) {
      final Uri url = _hostUri(host, '/fleet.json');
      final TransportOutcome outcome = await transport.send(
        HttpRequest(method: HttpMethod.get, url: url),
      );
      if (outcome is Received && outcome.response.status == 200) {
        final Map<String, Object?>? json = _jsonObject(outcome.response.body);
        if (json != null && json['catalogHosts'] is List) {
          return DocA.fromJson(json);
        }
      }
    }
    return null;
  }

  Future<DocC?> _fetchDocC(DocA docA, LpsmCoordinate coordinate) async {
    final String path = '/catalog/${coordinate.platform}.json';
    for (final String host in docA.catalogHosts) {
      final Uri url = _hostUri(host, path);
      final TransportOutcome outcome = await transport.send(
        HttpRequest(method: HttpMethod.get, url: url),
      );
      if (outcome is Received && outcome.response.status == 200) {
        final DocC? doc = DocC.tryDecode(outcome.response.body);
        if (doc != null) {
          return doc;
        }
      }
    }
    return null;
  }

  Uri _hostUri(String host, String path) => host.contains('://')
      ? Uri.parse('$host$path')
      : Uri.parse('https://$host$path');

  static Map<String, Object?>? _jsonObject(String body) {
    if (body.trim().isEmpty) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(body);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static bool _isNewer(int candidate, int? seen) =>
      seen == null || candidate > seen;

  static int? _parseInt(String? raw) => raw == null ? null : int.tryParse(raw);
}
