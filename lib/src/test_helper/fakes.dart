import '../client_tree.dart';
import '../config.dart';
import '../rescue/store.dart';
import '../transport.dart';

/// A scriptable, dependency-light fake transport. NO test-framework deps — it
/// implements the real [HttpTransport] seam so contract-parity meta suites can
/// run the SAME behavioural suite against this fake and a real transport.
///
/// Records every [HttpRequest] it sees (for asserting token attach / no
/// cross-backend bleed) and returns outcomes from a responder.
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

  /// Number of times [send] was called.
  int get callCount => sent.length;

  @override
  Future<TransportOutcome> send(HttpRequest request) async {
    sent.add(request);
    return _responder(request);
  }
}

/// A fake per-backend token retriever. Tokens are keyed by LPSM coordinate so
/// tests can prove per-backend resolution with NO cross-backend bleed.
class FakeAuth implements IAuth {
  FakeAuth(this._tokens);

  final Map<String, String> _tokens;

  /// Coordinates asked for a token, in order (for bleed assertions).
  final List<String> queried = <String>[];

  @override
  Future<String?> tokenFor(LpsmCoordinate coordinate,
      {String? resource}) async {
    queried.add(coordinate.key);
    return _tokens[coordinate.key];
  }
}

/// A rescue store that also exposes its backing map for assertions. Extends the
/// production [InMemoryRescueStore] so its behaviour is identical.
class FakeRescueStore extends InMemoryRescueStore {
  FakeRescueStore([super.seed]);

  final List<String> writes = <String>[];

  @override
  Future<void> write(String key, String value) async {
    writes.add(key);
    return super.write(key, value);
  }
}

/// A jitter function that never sleeps — for deterministic rescue-scan tests.
Duration noJitter() => Duration.zero;

/// A no-op sleep for deterministic rescue tests.
Future<void> noSleep(Duration duration) async {}

/// A monotonic fake clock (milliseconds) advanced explicitly by the test.
class FakeClock {
  FakeClock([this._ms = 0]);

  int _ms;

  int nowMs() => _ms;

  void advance(Duration by) => _ms += by.inMilliseconds;
}
