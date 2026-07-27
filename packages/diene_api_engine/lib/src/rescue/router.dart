import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../config.dart';
import '../transport.dart';
import 'docs.dart';
import 'store.dart';

/// Result of a rescue attempt.
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
/// frontend-utils machinery). It only runs after a hard connect-failure past
/// retry-once, and only when [RescueConfig.enabled] is true for the context.
///
/// Safety rails: the baked endpoint-suffix allowlist is enforced on EVERY
/// doc-sourced URL at use time — Doc-A-supplied catalog hosts (before the
/// Doc-C fetch) AND Doc-C candidate addresses. Monotonic doc versions (older
/// rejected); always-baked issuer (never doc-sourced); last-known-good kept
/// forever; jittered, strictly-budgeted scan (a hanging probe cannot exceed the
/// global scan budget); same landscape only; addresses only; no doc signing.
class RescueRouter {
  RescueRouter({
    required this.config,
    required this.store,
    required this.transport,
    Future<void> Function(Duration duration)? sleep,
    int Function()? nowMs,
    Duration Function()? jitter,
    Random? random,
  }) : _sleep = sleep ?? Future<void>.delayed,
       _nowMs = nowMs ?? _wallClockMs,
       _random = random ?? Random(),
       _jitterOverride = jitter;

  final RescueConfig config;
  final RescueStore store;
  final HttpTransport transport;
  final Future<void> Function(Duration duration) _sleep;
  final int Function() _nowMs;
  final Random _random;
  final Duration Function()? _jitterOverride;

  static int _wallClockMs() => DateTime.now().millisecondsSinceEpoch;

  // Doc A is the ONE fleet doc (host list) — its monotonic version is global.
  static const String _docAVersionKey = 'doca.version';

  // Doc C is per platform × environment(landscape): cache + version keys are
  // scoped by that partition so N backends across platforms/landscapes never
  // reuse another partition's catalog.
  String _docCScope(LpsmCoordinate c) => '${c.platform}.${c.landscape}';
  String _docCKey(LpsmCoordinate c) => 'docc.${_docCScope(c)}';
  String _docCVersionKey(LpsmCoordinate c) => 'docc.version.${_docCScope(c)}';
  String _pinKey(LpsmCoordinate c) => 'pin.${c.key}';
  String _lastGoodKey(LpsmCoordinate c) => 'lastgood.${c.key}';

  /// The always-baked issuer. Exposed so callers can assert it is never read
  /// from a doc.
  Uri get bakedIssuer => config.issuer;

  /// Production jitter drawn from `[0, maxJitter]`, or the injected
  /// deterministic source in tests.
  Duration nextJitter() {
    if (_jitterOverride != null) {
      return _jitterOverride();
    }
    final int maxMs = config.maxJitter.inMilliseconds;
    return maxMs <= 0
        ? Duration.zero
        : Duration(milliseconds: _random.nextInt(maxMs + 1));
  }

  /// Enforce the baked endpoint-suffix allowlist on a doc-sourced URL/host.
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
  /// allowlisted (pin-until-primary-heals).
  Future<Uri?> pinnedFor(LpsmCoordinate coordinate) async {
    final String? raw = await store.read(_pinKey(coordinate));
    if (raw == null) {
      return null;
    }
    final Uri url = Uri.parse(raw);
    return isAllowed(url) ? url : null;
  }

  /// Clear the pin once the primary home root heals.
  Future<void> onPrimaryHealed(LpsmCoordinate coordinate) =>
      store.delete(_pinKey(coordinate));

  /// Probe whether a base URL is reachable (a received status < 500).
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

    // Allowlist enforced at USE time on Doc-C candidates.
    final List<Uri> candidates = <Uri>[
      if (docC != null)
        ...?docC.candidates[coordinate.key]?.map(Uri.parse).where(isAllowed),
    ];

    final int start = _nowMs();
    final int deadline = start + config.scanBudget.inMilliseconds;
    for (final Uri candidate in candidates) {
      // Jitter counts toward the budget.
      await _sleep(nextJitter());
      final int remaining = deadline - _nowMs();
      if (remaining <= 0) {
        break; // global budget exhausted
      }
      // Per-candidate timeout, capped so even a hanging probe cannot push the
      // scan past the global budget.
      final Duration cap = Duration(
        milliseconds: remaining < config.perCandidateTimeout.inMilliseconds
            ? remaining
            : config.perCandidateTimeout.inMilliseconds,
      );
      if (await _probeWithinBudget(candidate, cap)) {
        await _pin(coordinate, candidate);
        return Rescued(candidate, fromLastKnownGood: false);
      }
    }

    // No fresh candidate healthy within budget — fall back to last-known-good,
    // kept forever and still allowlisted.
    if (lastGood != null && isAllowed(lastGood)) {
      return Rescued(lastGood, fromLastKnownGood: true);
    }
    return const RescueUnavailable(
      'no healthy candidate within budget and no last-known-good',
    );
  }

  /// Probe [candidate] but never wait longer than [cap]. A hanging probe loses
  /// to the timeout (fail-closed → unhealthy) so the global budget is honoured.
  Future<bool> _probeWithinBudget(Uri candidate, Duration cap) async {
    final Completer<bool> done = Completer<bool>();
    unawaited(
      probeHealthy(candidate).then(
        (bool healthy) {
          if (!done.isCompleted) {
            done.complete(healthy);
          }
        },
        onError: (_, _) {
          if (!done.isCompleted) {
            done.complete(false);
          }
        },
      ),
    );
    unawaited(
      _sleep(cap).then((_) {
        if (!done.isCompleted) {
          done.complete(false);
        }
      }),
    );
    return done.future;
  }

  Future<Uri?> _lastKnownGood(LpsmCoordinate coordinate) async {
    final String? raw = await store.read(_lastGoodKey(coordinate));
    return raw == null ? null : Uri.parse(raw);
  }

  Future<void> _pin(LpsmCoordinate coordinate, Uri url) async {
    await store.write(_pinKey(coordinate), url.toString());
    await store.write(_lastGoodKey(coordinate), url.toString());
  }

  /// Load Doc C (per platform × landscape) from disk (cached forever) and
  /// opportunistically refresh it via Doc A's catalog hosts. The per-scope Doc C
  /// fetch is INDEPENDENT of the fleet Doc A version advancing — otherwise a
  /// second platform sharing one router would reuse the first platform's
  /// catalog once Doc A settled. Monotonic versions are honoured PER SCOPE (Doc
  /// C) and fleet-wide (Doc A: an older Doc A is a rollback and is rejected).
  Future<DocC?> _loadOrRefreshDocC(LpsmCoordinate coordinate) async {
    DocC? cached;
    final String? cachedRaw = await store.read(_docCKey(coordinate));
    if (cachedRaw != null) {
      cached = DocC.tryDecode(cachedRaw);
    }
    final int? seenDocC = _parseInt(
      await store.read(_docCVersionKey(coordinate)),
    );

    final DocA? docA = await _fetchDocA();
    if (docA != null) {
      final DocC? fetched = await _fetchDocC(docA, coordinate);
      if (fetched != null && _isNewer(fetched.version, seenDocC)) {
        await store.write(_docCKey(coordinate), fetched.encode());
        await store.write(
          _docCVersionKey(coordinate),
          fetched.version.toString(),
        );
        return fetched;
      }
    }
    return cached;
  }

  /// Fetch the fleet Doc A (host list) from the baked catalog hosts. Monotonic:
  /// a Doc A OLDER than the last seen fleet version is a rollback and is
  /// rejected; a Doc A at or above the seen version is usable (its hosts drive
  /// the per-scope Doc C fetch), and the fleet version advances only on a
  /// strictly-newer Doc A.
  Future<DocA?> _fetchDocA() async {
    final int? seenDocA = _parseInt(await store.read(_docAVersionKey));
    for (final String host in config.catalogHosts) {
      final Uri url = _hostUri(host, '/fleet.json');
      if (!isAllowed(url)) {
        continue;
      }
      final TransportOutcome outcome = await transport.send(
        HttpRequest(method: HttpMethod.get, url: url),
      );
      if (outcome is Received && outcome.response.status == 200) {
        final Map<String, Object?>? json = _jsonObject(outcome.response.body);
        if (json != null && json['catalogHosts'] is List) {
          final DocA docA = DocA.fromJson(json);
          if (seenDocA != null && docA.version < seenDocA) {
            return null; // rollback — reject
          }
          if (_isNewer(docA.version, seenDocA)) {
            await store.write(_docAVersionKey, docA.version.toString());
          }
          return docA;
        }
      }
    }
    return null;
  }

  Future<DocC?> _fetchDocC(DocA docA, LpsmCoordinate coordinate) async {
    final String path = '/catalog/${coordinate.platform}.json';
    for (final String host in docA.catalogHosts) {
      final Uri url = _hostUri(host, path);
      // Doc-A-SUPPLIED (doc-sourced) host — MUST be allowlisted before use, so
      // a poisoned Doc A cannot redirect the Doc-C fetch off the baked roots.
      if (!isAllowed(url)) {
        continue;
      }
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
