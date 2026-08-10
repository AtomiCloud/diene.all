/// The last reachable unit-ledger lines: bridge edge cases, the rescue router's
/// production jitter and malformed-document handling, `DocA` encoding, and the
/// client tree's enumeration accessor.
///
/// Each of these was uncovered because it needed a specific provocation — an
/// oversized error body, a structurally problem-ish but invalid envelope, a
/// non-zero jitter bound, a malformed cached document. None is dead code.
library;

import 'dart:convert';

import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

LpsmCoordinate _coord(String module) => LpsmCoordinate(
  landscape: 'lapras',
  platform: 'platform',
  service: 'service',
  module: module,
);

Map<String, Object?> _id(Map<String, Object?> json) => json;

void main() {
  group('bridge edge cases', () {
    test('an error body over 256 bytes is TRUNCATED with an ellipsis', () {
      // The snippet exists so a huge upstream error page cannot be copied whole
      // into a Problem; without a long body the truncation branch never runs.
      final String huge = 'x' * 900;

      final Result<Map<String, Object?>> result =
          toResult<Map<String, Object?>>(
            Received(HttpResponse(status: 502, body: huge)),
            decode: _id,
            endpoint: '/thing',
          );

      final String snippet = expectErr(result).data['bodySnippet']! as String;
      expect(snippet.length, lessThan(huge.length));
      expect(snippet.endsWith('…'), isTrue);
      expect(snippet.substring(0, 256), 'x' * 256);
    });

    test('a short error body is carried WHOLE, with no ellipsis', () {
      // The other side of the same branch, so "truncated" cannot be the only
      // behaviour ever observed.
      final Result<Map<String, Object?>> result =
          toResult<Map<String, Object?>>(
            Received(const HttpResponse(status: 502, body: 'Bad Gateway')),
            decode: _id,
            endpoint: '/thing',
          );

      expect(expectErr(result).data['bodySnippet'], 'Bad Gateway');
    });

    test('a problem body MISSING title still decodes, with defaults', () {
      // CORRECTION TO MY OWN ASSUMPTION, kept because the measurement is the
      // point. I wrote this first expecting a title-less body to make
      // `Problem.fromJson` throw a FormatException, which `toResult` catches and
      // falls through to unexpected-response. It does not: the published
      // `diene_problems` 0.1.1 `fromJson` DEFAULTS every field
      // (`type ?? 'about:blank'`, `title ?? 'Unexpected problem'`,
      // `status ?? 500`) and contains ZERO throw sites, so the envelope is
      // accepted as-is. The test now asserts what actually happens.
      //
      // Consequence recorded rather than worked around: `bridge.dart:117`'s
      // `on FormatException` branch is UNREACHABLE against this dependency
      // version. It is defensive depth, not a test gap, and it is left in place
      // — a future `diene_problems` that validates strictly would need it. It is
      // reported as provably-unreachable instead of being covered by contorting
      // the code or masked with a pragma.
      final Result<Map<String, Object?>> result =
          toResult<Map<String, Object?>>(
            Received(
              HttpResponse(
                status: 400,
                body: jsonEncode(<String, Object?>{
                  'type': 'urn:example:problem',
                  'status': 400,
                  'data': <String, Object?>{'k': 'v'},
                }),
              ),
            ),
            decode: _id,
            endpoint: '/thing',
          );

      final Problem got = expectErr(result);
      expect(got.type, 'urn:example:problem');
      expect(got.status, 400);
      expect(got.title, 'Unexpected problem', reason: 'the defaulted title');
      expect(got.data['k'], 'v', reason: 'the data extension survives');
    });

    test('a transport failure with NO endpoint omits the endpoint key', () {
      final Result<Map<String, Object?>> result =
          toResult<Map<String, Object?>>(networkFailure('down'), decode: _id);

      expect(expectErr(result).data.containsKey('endpoint'), isFalse);
    });
  });

  group('rescue router jitter and document handling', () {
    RescueConfig config({
      Duration maxJitter = const Duration(milliseconds: 40),
    }) => RescueConfig(
      enabled: true,
      issuer: Uri.parse('https://auth.example.com'),
      catalogHosts: const <String>['https://seed.example.com'],
      endpointSuffixAllowlist: const <String>['.example.com'],
      maxJitter: maxJitter,
    );

    test('production jitter stays within [0, maxJitter]', () {
      // No injected override, so the REAL random path runs. Sampled repeatedly
      // because a single draw could land inside the bound by luck.
      final RescueRouter router = RescueRouter(
        config: config(),
        store: FakeRescueStore(),
        transport: FakeHttpTransport((HttpRequest _) => networkFailure()),
        sleep: noSleep,
        nowMs: FakeClock().nowMs,
      );

      for (int i = 0; i < 50; i += 1) {
        final Duration drawn = router.nextJitter();
        expect(drawn, greaterThanOrEqualTo(Duration.zero));
        expect(drawn, lessThanOrEqualTo(const Duration(milliseconds: 40)));
      }
    });

    test('a zero maxJitter yields exactly zero, never a random draw', () {
      // The `maxMs <= 0` guard: without this case, a misconfigured zero bound
      // could reach `nextInt(1)` or throw and nobody would know.
      final RescueRouter router = RescueRouter(
        config: config(maxJitter: Duration.zero),
        store: FakeRescueStore(),
        transport: FakeHttpTransport((HttpRequest _) => networkFailure()),
        sleep: noSleep,
        nowMs: FakeClock().nowMs,
      );

      expect(router.nextJitter(), Duration.zero);
    });

    test('a MALFORMED cached document is ignored rather than thrown', () {
      // A corrupted on-disk cache must not crash the app; DocC.tryDecode is the
      // fail-soft seam and its FormatException branch was unexercised.
      expect(DocC.tryDecode('{not json at all'), isNull);
      expect(DocC.tryDecode('[]'), isNull);
    });
  });

  group('DocA encoding', () {
    test('round-trips through toJson', () {
      // DocA.toJson had no coverage: nothing ever serialised a Doc A back out,
      // yet the router writes it to the disk cache.
      const DocA doc = DocA(
        version: 7,
        catalogHosts: <String>['https://a.example.com'],
      );

      final Map<String, Object?> json = doc.toJson();

      expect(json['version'], 7);
      expect(json['catalogHosts'], <String>['https://a.example.com']);
      expect(DocA.fromJson(json).version, 7);
      expect(DocA.fromJson(json).catalogHosts, doc.catalogHosts);
    });
  });

  group('client tree enumeration', () {
    test('backends exposes every registered BackendConfig', () {
      final ClientTree tree = ClientTree();
      final BackendConfig a = BackendConfig(
        coordinate: _coord('a'),
        baseUrl: Uri.parse('https://a.example.com'),
      );
      final BackendConfig b = BackendConfig(
        coordinate: _coord('b'),
        baseUrl: Uri.parse('https://b.example.com'),
      );

      // `register` returns `Result<void>`, so its Ok payload cannot be compared
      // as a value — assert on the outcome instead.
      expect(tree.register(a).isOk, isTrue);
      expect(tree.register(b).isOk, isTrue);

      expect(tree.backends, hasLength(2));
      expect(
        tree.backends.map((BackendConfig c) => c.coordinate.module).toSet(),
        <String>{'a', 'b'},
      );
    });
  });
}
