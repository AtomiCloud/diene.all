import 'dart:convert';

import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Transport-level regressions for the HTTP Doc B source and region pinger. Both
// take an injected `http.Client`, so every branch runs against a MockClient with
// no live edge — the allowlist gate, the status gate, the shape gate, and the
// pinger's healthy / unhealthy / transport-error / timeout arms.
void main() {
  final AuthEngineConfig config = AuthEngineConfig.fromBlock(<String, Object?>{
    'issuer': 'https://api.lithium.platform.mew.cluster.atomi.cloud',
    'endpoint': 'https://logto.example.com',
    'appId': 'mobile',
    'redirectUri': 'cloud.atomi.app://callback',
  });
  final Uri docUrl = Uri.parse(
    'https://edge.lithium.lapras.cluster.atomi.cloud/landscapes.json',
  );

  String docBody({
    String platform = 'lithium',
    String tier = 'lapras',
    List<Map<String, Object?>> landscapes = const <Map<String, Object?>>[
      <String, Object?>{'name': 'pichu', 'region': 'ap-southeast-1'},
    ],
  }) => jsonEncode(<String, Object?>{
    'platform': platform,
    'tier': tier,
    'landscapes': landscapes,
  });

  group('HttpLandscapeSelectorSource', () {
    test('fetches and parses an allowlisted Doc B', () async {
      // Arrange
      Uri? requested;
      final HttpLandscapeSelectorSource source = HttpLandscapeSelectorSource(
        docUrl: docUrl,
        config: config,
        client: MockClient((http.Request request) async {
          requested = request.url;
          return http.Response(docBody(), 200);
        }),
      );

      // Act
      final LandscapeSelectorDoc doc = await source.fetch();

      // Assert
      expect(requested, docUrl);
      expect(doc.platform, 'lithium');
      expect(doc.tier, 'lapras');
      expect(doc.landscapes.single.name, 'pichu');
    });

    test('refuses a doc URL outside the baked endpoint-suffix allowlist BEFORE '
        'fetching', () async {
      // Arrange — an attacker-supplied host must never even be contacted.
      int calls = 0;
      final HttpLandscapeSelectorSource source = HttpLandscapeSelectorSource(
        docUrl: Uri.parse('https://evil.example.com/landscapes.json'),
        config: config,
        client: MockClient((http.Request request) async {
          calls += 1;
          return http.Response(docBody(), 200);
        }),
      );

      // Act + Assert
      await expectLater(source.fetch(), throwsFormatException);
      expect(calls, 0);
    });

    test('rejects a non-200 Doc B response', () async {
      // Arrange
      final HttpLandscapeSelectorSource source = HttpLandscapeSelectorSource(
        docUrl: docUrl,
        config: config,
        client: MockClient(
          (http.Request request) async => http.Response('nope', 503),
        ),
      );

      // Act + Assert
      await expectLater(source.fetch(), throwsA(isA<http.ClientException>()));
    });

    test('rejects a Doc B body that is not a JSON object', () async {
      // Arrange — a JSON array is well-formed JSON but the wrong shape.
      final HttpLandscapeSelectorSource source = HttpLandscapeSelectorSource(
        docUrl: docUrl,
        config: config,
        client: MockClient(
          (http.Request request) async => http.Response('[1,2,3]', 200),
        ),
      );

      // Act + Assert
      await expectLater(source.fetch(), throwsFormatException);
    });

    test('normalizes non-string top-level doc keys before parsing', () async {
      // Arrange — jsonDecode yields Map<String, dynamic>, but the source maps
      // keys defensively; a doc whose keys survive that mapping still parses.
      final HttpLandscapeSelectorSource source = HttpLandscapeSelectorSource(
        docUrl: docUrl,
        config: config,
        client: MockClient(
          (http.Request request) async => http.Response(
            docBody(
              landscapes: const <Map<String, Object?>>[
                <String, Object?>{
                  'name': 'pichu',
                  'region': 'ap-southeast-1',
                  'metadata': <String, Object?>{'flavour': 'edge'},
                },
                <String, Object?>{'name': 'raichu', 'region': 'us-east-1'},
              ],
            ),
            200,
          ),
        ),
      );

      // Act
      final LandscapeSelectorDoc doc = await source.fetch();

      // Assert
      expect(doc.landscapes.map((LandscapeEntry e) => e.name), <String>[
        'pichu',
        'raichu',
      ]);
      expect(doc.landscapes.first.metadata['flavour'], 'edge');
    });

    test('defaults to a real http.Client when none is injected', () {
      // Arrange + Act — construction must do NO network work, so the default
      // client arm is safe to exercise without a live edge.
      final HttpLandscapeSelectorSource source = HttpLandscapeSelectorSource(
        docUrl: docUrl,
        config: config,
      );

      // Assert
      expect(source, isA<LandscapeSelectorSource>());
    });
  });

  group('HttpRegionPinger', () {
    const LandscapeEntry entry = LandscapeEntry(
      name: 'pichu',
      region: 'ap-southeast-1',
    );
    Uri pingUrlOf(LandscapeEntry e) =>
        Uri.parse('https://api.lithium.${e.name}.cluster.atomi.cloud/health');

    test('returns the round-trip latency for a healthy 2xx region', () async {
      // Arrange — a deterministic stopwatch so the asserted latency is exact.
      Uri? requested;
      final HttpRegionPinger pinger = HttpRegionPinger(
        pingUrlOf: pingUrlOf,
        client: MockClient((http.Request request) async {
          requested = request.url;
          return http.Response('ok', 204);
        }),
        stopwatch: () => _FixedStopwatch(const Duration(milliseconds: 42)),
      );

      // Act
      final Duration? latency = await pinger.ping(entry);

      // Assert — the ping URL is DERIVED from the name, never doc-carried.
      expect(requested, pingUrlOf(entry));
      expect(latency, const Duration(milliseconds: 42));
    });

    test('treats a non-2xx region as unhealthy', () async {
      // Arrange
      final HttpRegionPinger pinger = HttpRegionPinger(
        pingUrlOf: pingUrlOf,
        client: MockClient(
          (http.Request request) async => http.Response('down', 500),
        ),
      );

      // Act + Assert
      expect(await pinger.ping(entry), isNull);
    });

    test('treats a 3xx region as unhealthy', () async {
      // Arrange — the healthy window is exactly [200, 300).
      final HttpRegionPinger pinger = HttpRegionPinger(
        pingUrlOf: pingUrlOf,
        client: MockClient(
          (http.Request request) async => http.Response('moved', 302),
        ),
      );

      // Act + Assert
      expect(await pinger.ping(entry), isNull);
    });

    test('swallows a transport error and reports unhealthy', () async {
      // Arrange
      final HttpRegionPinger pinger = HttpRegionPinger(
        pingUrlOf: pingUrlOf,
        client: MockClient(
          (http.Request request) async =>
              throw http.ClientException('connection refused'),
        ),
      );

      // Act + Assert — an unreachable region is null, never an exception.
      expect(await pinger.ping(entry), isNull);
    });

    test('swallows a timeout and reports unhealthy', () async {
      // Arrange — a client that outlives the ping budget.
      final HttpRegionPinger pinger = HttpRegionPinger(
        pingUrlOf: pingUrlOf,
        client: MockClient((http.Request request) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return http.Response('late', 200);
        }),
        timeout: const Duration(milliseconds: 10),
      );

      // Act + Assert
      expect(await pinger.ping(entry), isNull);
    });

    test('defaults to a real http.Client and Stopwatch when none are '
        'injected', () {
      // Arrange + Act — construction alone must do no network work.
      final HttpRegionPinger pinger = HttpRegionPinger(pingUrlOf: pingUrlOf);

      // Assert
      expect(pinger, isA<RegionPinger>());
    });
  });
}

/// Stopwatch whose [elapsed] is a fixed value, so a latency assertion is exact
/// rather than wall-clock dependent.
final class _FixedStopwatch implements Stopwatch {
  _FixedStopwatch(this._elapsed);

  final Duration _elapsed;
  bool _running = false;

  @override
  Duration get elapsed => _elapsed;

  @override
  void start() => _running = true;

  @override
  void stop() => _running = false;

  @override
  void reset() {}

  @override
  bool get isRunning => _running;

  @override
  int get elapsedMicroseconds => _elapsed.inMicroseconds;

  @override
  int get elapsedMilliseconds => _elapsed.inMilliseconds;

  @override
  int get elapsedTicks => _elapsed.inMicroseconds;

  @override
  int get frequency => Duration.microsecondsPerSecond;
}
