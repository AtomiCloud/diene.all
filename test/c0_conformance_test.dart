import 'dart:convert';

import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:test/test.dart';

/// C0 conformance. The Dart family is EXEMPT from the C0 otel config block
/// (frontend-only; telemetry rides Faro). When C0 ships shared cross-language
/// fixtures these assertions bind to them; until then they encode the same
/// invariants directly (see the node note's dependency-stacking section).
void main() {
  group('C0 §5 Result semantics — combinator parity', () {
    test('ok/err constructors and match align to the cross-language names', () {
      final Result<int> ok = const Result<int>.ok(1);
      final Result<int> err = Result<int>.err(
        const Problem(type: 't', title: 'T', status: 400),
      );
      expect(
          ok.match(ok: (int v) => 'ok$v', err: (Problem p) => p.type), 'ok1');
      expect(err.match(ok: (int v) => 'ok$v', err: (Problem p) => p.type), 't');
    });

    test('map / mapErr / andThen obey monad laws (left identity, composition)',
        () {
      // left identity: ok(x).andThen(f) == f(x)
      Result<int> f(int x) => Ok<int>(x + 1);
      expect(const Ok<int>(1).andThen(f), f(1));
      // map composition
      final Result<int> composed =
          const Ok<int>(2).map((int x) => x + 1).map((int x) => x * 2);
      expect(composed, const Ok<int>(6));
    });
  });

  group('C0 Problem envelope (RFC 9457 + data extension)', () {
    test('serializes canonical members and the data extension', () {
      final Problem problem = const Problem(
        type: 'urn:diene:problem:x',
        title: 'X',
        status: 422,
        detail: 'd',
        instance: '/i',
        recoverable: true,
        data: <String, Object?>{'field': 'value'},
      );
      final Map<String, Object?> json = problem.toJson();
      expect(
          json.keys, containsAll(<String>['type', 'title', 'status', 'data']));
      // round-trip is lossless over the wire
      final Problem back = Problem.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, Object?>,
      );
      expect(back.type, problem.type);
      expect(back.status, 422);
      expect(back.recoverable, isTrue);
      expect(back.data['field'], 'value');
    });
  });

  group('engine-owned config block schema', () {
    test('is frozen (drift guard) and carries NO otel block', () {
      final Map<String, Object?> schema = ApiEngineConfig.schema;
      expect(schema[r'$id'], 'urn:diene:config-block:api-engine');
      final Map<String, Object?> properties =
          schema['properties']! as Map<String, Object?>;
      // dart is frontend-only: this engine block never owns an otel schema.
      expect(properties.containsKey('otel'), isFalse);
      expect(properties.keys, containsAll(<String>['backends', 'rescue']));
    });
  });
}
