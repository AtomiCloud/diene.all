import 'package:diene_flutter_base/core/result.dart';
import 'package:diene_flutter_base/integration/observability_wiring.dart';
import 'package:diene_flutter_base/observability/faro.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

/// Records what init actually fired with, so the gate asserts on values rather
/// than on the initializer merely returning.
final class _RecordingFaroTransport implements FaroTransport {
  int initCalls = 0;
  Uri? collectorUrl;
  String? apiKey;
  Map<String, String>? attributes;
  final List<(String, Map<String, String>)> measurements =
      <(String, Map<String, String>)>[];

  @override
  Future<void> initialize({
    required Uri collectorUrl,
    required Map<String, String> attributes,
    String? apiKey,
  }) async {
    initCalls += 1;
    this.collectorUrl = collectorUrl;
    this.attributes = attributes;
    this.apiKey = apiKey;
  }

  @override
  void pushMeasurement(String name, {required Map<String, String> attributes}) {
    measurements.add((name, attributes));
  }
}

final class _ThrowingFaroTransport implements FaroTransport {
  @override
  Future<void> initialize({
    required Uri collectorUrl,
    required Map<String, String> attributes,
    String? apiKey,
  }) async => throw StateError('collector unreachable');

  @override
  void pushMeasurement(String name, {required Map<String, String> attributes}) {
    throw StateError('not initialised');
  }
}

final Uri _collector = Uri.parse('https://faro.example.invalid/collect');

ObservabilityLabels _labels() =>
    ObservabilityLabels.fromIdentity(testConfig().identity);

void main() {
  group('faro initialization fires with LPSM attrs', () {
    test('init fires exactly once, at the collector, with LPSM attrs', () async {
      final _RecordingFaroTransport transport = _RecordingFaroTransport();
      final Result<FaroSession> result = await FaroInitializer(
        transport: transport,
        config: FaroConfig(collectorUrl: _collector, apiKey: 'secret-key'),
      ).initialize(_labels());

      final FaroSession session = result.fold<FaroSession>(
        onSuccess: (FaroSession value) => value,
        onFailure: (Problem problem) =>
            fail('expected init to succeed, got ${problem.type}'),
      );

      // Init observably fired — once, at the configured collector, with the key.
      expect(transport.initCalls, 1);
      expect(transport.collectorUrl, _collector);
      expect(transport.apiKey, 'secret-key');

      // ...and carried every LPSM label, with the Faro app-meta keys derived
      // from them. This is the assertion that goes RED if init wiring breaks.
      expect(transport.attributes, <String, String>{
        'landscape': 'lapras',
        'platform': 'platform',
        'service': 'service',
        'module': 'app',
        'version': '1.0.0',
        'app_name': 'app',
        'app_namespace': 'service',
        'app_version': '1.0.0',
        'app_environment': 'lapras',
        'app_platform': 'platform',
      });
      expect(session.attributes, transport.attributes);
      expect(session.collectorUrl, _collector);
      expect(session.labels, _labels());
    });

    test('the LPSM label map is a strict subset of the faro attributes', () {
      final ObservabilityLabels labels = _labels();
      final Map<String, String> attributes = FaroInitializer.attributesFor(
        labels,
      );

      for (final MapEntry<String, String> entry
          in labels.toLabelMap().entries) {
        expect(
          attributes[entry.key],
          entry.value,
          reason: 'LPSM label ${entry.key} must survive into faro attributes',
        );
      }
      expect(attributes.length, labels.toLabelMap().length + 5);
    });

    test('every signal through the session sink carries the attrs', () async {
      final _RecordingFaroTransport transport = _RecordingFaroTransport();
      final Result<FaroSession> result = await FaroInitializer(
        transport: transport,
        config: FaroConfig(collectorUrl: _collector),
      ).initialize(_labels());
      final FaroSession session = result.fold<FaroSession>(
        onSuccess: (FaroSession value) => value,
        onFailure: (Problem problem) => fail('init failed: ${problem.type}'),
      );

      ObservabilityContext(
        labels: session.labels,
        sink: session.sink,
      ).emit('app.start', extra: <String, String>{'screen': 'home'});

      expect(transport.measurements.length, 1);
      final (String name, Map<String, String> attrs) =
          transport.measurements.single;
      expect(name, 'app.start');
      expect(attrs['screen'], 'home');
      expect(attrs['landscape'], 'lapras');
      expect(attrs['app_name'], 'app');
      expect(attrs['app_version'], '1.0.0');
    });

    test('disabled telemetry never touches the collector', () async {
      final _RecordingFaroTransport transport = _RecordingFaroTransport();
      final Result<FaroSession> result = await FaroInitializer(
        transport: transport,
        config: FaroConfig(collectorUrl: _collector, enabled: false),
      ).initialize(_labels());

      expect(result.isSuccess, isFalse);
      expect(transport.initCalls, 0);
      final Problem problem = result.fold<Problem>(
        onSuccess: (FaroSession _) => fail('expected a disabled failure'),
        onFailure: (Problem value) => value,
      );
      expect(problem.type, 'urn:diene:problem:faro-disabled');
      expect(problem.recoverable, isTrue);
    });

    test('a blank LPSM label is refused before the collector is hit', () async {
      final _RecordingFaroTransport transport = _RecordingFaroTransport();
      final Result<FaroSession> result = await FaroInitializer(
        transport: transport,
        config: FaroConfig(collectorUrl: _collector),
      ).initialize(
        const ObservabilityLabels(
          landscape: 'lapras',
          platform: '  ',
          service: 'service',
          module: '',
          version: '1.0.0',
        ),
      );

      expect(transport.initCalls, 0);
      final Problem problem = result.fold<Problem>(
        onSuccess: (FaroSession _) => fail('expected an identity failure'),
        onFailure: (Problem value) => value,
      );
      expect(problem.type, 'urn:diene:problem:faro-identity-incomplete');
      expect(problem.status, 500);
      expect(problem.data['missing'], <String>['platform', 'module']);
    });

    test('a throwing transport becomes a Failure, not an exception', () async {
      final Result<FaroSession> result = await FaroInitializer(
        transport: _ThrowingFaroTransport(),
        config: FaroConfig(collectorUrl: _collector),
      ).initialize(_labels());

      final Problem problem = result.fold<Problem>(
        onSuccess: (FaroSession _) => fail('expected an init failure'),
        onFailure: (Problem value) => value,
      );
      expect(problem.type, 'urn:diene:problem:faro-init-failed');
      expect(problem.detail, contains('collector unreachable'));
      expect(problem.data['collector'], _collector.toString());
    });

    test('the no-op transport keeps init succeeding with no collector', () async {
      final Result<FaroSession> result = await FaroInitializer(
        transport: const NoopFaroTransport(),
        config: FaroConfig(collectorUrl: _collector),
      ).initialize(_labels());

      expect(result.isSuccess, isTrue);
    });
  });
}
