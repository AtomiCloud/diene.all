import 'dart:async';

import 'package:diene_auth_engine/diene_auth_engine.dart'
    show IAuth, ResourceKey, ResourceToken;
import 'package:diene_problems/diene_problems.dart' show Problem;
import 'package:diene_result/diene_result.dart';

import '../rescue/store.dart';
import '../transport.dart';

/// A scriptable, dependency-light fake transport implementing the real
/// [HttpTransport] seam, so a contract-parity suite runs the SAME behaviour
/// against this fake and a real transport. Records every request.
class FakeHttpTransport implements HttpTransport {
  FakeHttpTransport(this._responder);

  /// Replay a fixed sequence of outcomes, one per call (last repeats).
  factory FakeHttpTransport.sequence(List<TransportOutcome> outcomes) {
    var index = 0;
    return FakeHttpTransport((HttpRequest _) {
      final TransportOutcome outcome =
          outcomes[index < outcomes.length ? index : outcomes.length - 1];
      index++;
      return outcome;
    });
  }

  /// Route outcomes by request host; falls back to [orElse].
  factory FakeHttpTransport.byHost(
    Map<String, TransportOutcome> byHost, {
    TransportOutcome orElse = const NetworkFailure('unmapped host'),
  }) =>
      FakeHttpTransport(
        (HttpRequest request) => byHost[request.url.host] ?? orElse,
      );

  final TransportOutcome Function(HttpRequest request) _responder;

  /// Every request the transport handled, in order.
  final List<HttpRequest> sent = <HttpRequest>[];

  int get callCount => sent.length;

  @override
  Future<TransportOutcome> send(HttpRequest request) async {
    sent.add(request);
    return _responder(request);
  }
}

/// A transport whose probes NEVER complete — used to prove the rescue scan's
/// per-candidate/global budget bounds a hanging probe.
class HangingTransport implements HttpTransport {
  final List<HttpRequest> sent = <HttpRequest>[];

  @override
  Future<TransportOutcome> send(HttpRequest request) {
    sent.add(request);
    return Completer<TransportOutcome>().future; // never completes
  }
}

/// A fake per-resource token retriever implementing the real [IAuth] seam.
/// Tokens are keyed by [ResourceKey.mapKey] so tests prove per-resource
/// resolution with NO cross-backend bleed. Unknown keys fail closed ([Err]).
class FakeAuth implements IAuth {
  FakeAuth(this._tokens, {DateTime? expiresAt})
      : _expiresAt = expiresAt ?? DateTime.utc(2999);

  final Map<String, String> _tokens;
  final DateTime _expiresAt;

  /// Resource map-keys asked for a token, in order (for bleed assertions).
  final List<String> queried = <String>[];

  @override
  Future<Result<ResourceToken>> tokenFor(ResourceKey key) async {
    queried.add(key.mapKey);
    final String? token = _tokens[key.mapKey];
    if (token == null) {
      return Err<ResourceToken>(
        Problem(
          type: 'urn:diene:test:no-token',
          title: 'No token',
          status: 401,
          detail: key.mapKey,
        ),
      );
    }
    return Ok<ResourceToken>(
        ResourceToken(token: token, expiresAt: _expiresAt));
  }

  @override
  Future<Map<ResourceKey, Result<ResourceToken>>> fetchAllTokens(
    Iterable<ResourceKey> keys,
  ) async {
    final Map<ResourceKey, Result<ResourceToken>> out =
        <ResourceKey, Result<ResourceToken>>{};
    for (final ResourceKey key in keys) {
      out[key] = await tokenFor(key);
    }
    return out;
  }

  @override
  void invalidateAll() {}

  @override
  void invalidate(ResourceKey key) {}
}

/// A rescue store exposing its backing map + write log for assertions.
class FakeRescueStore extends InMemoryRescueStore {
  FakeRescueStore([super.seed]);

  final List<String> writes = <String>[];

  @override
  Future<void> write(String key, String value) async {
    writes.add(key);
    return super.write(key, value);
  }
}

/// Zero jitter — deterministic rescue-scan ordering.
Duration noJitter() => Duration.zero;

/// A no-op sleep for deterministic rescue tests.
Future<void> noSleep(Duration duration) async {}

/// A monotonic fake clock (milliseconds) advanced explicitly or by a sleep.
class FakeClock {
  FakeClock([this._ms = 0]);

  int _ms;

  int nowMs() => _ms;

  void advance(Duration by) => _ms += by.inMilliseconds;

  /// A `sleep` that advances this clock and completes immediately — lets budget
  /// tests exercise real timing math with no wall-clock wait.
  Future<void> sleep(Duration duration) async => advance(duration);
}
