import 'package:diene_flutter_base/config/app_config.dart';
import 'package:diene_flutter_base/integration/integration.dart';
import 'package:flutter_test/flutter_test.dart';

const AppIdentityConfig _identity = AppIdentityConfig(
  landscape: 'lapras',
  platform: 'platform',
  service: 'service',
  module: 'app',
  version: '1.0.0',
);

void main() {
  group(
    'observability wiring (stands live on flutter-base + observability)',
    () {
      test('projects the canonical LPSM label set from app identity', () {
        final ObservabilityLabels labels = ObservabilityLabels.fromIdentity(
          _identity,
        );

        expect(labels.toLabelMap(), <String, String>{
          'landscape': 'lapras',
          'platform': 'platform',
          'service': 'service',
          'module': 'app',
          'version': '1.0.0',
        });
      });

      test('label map ordering is deterministic (LPSM then version)', () {
        final ObservabilityLabels labels = ObservabilityLabels.fromIdentity(
          _identity,
        );

        expect(labels.toLabelMap().keys.toList(), <String>[
          'landscape',
          'platform',
          'service',
          'module',
          'version',
        ]);
      });

      test('equal label sets are equal and hash equally', () {
        expect(
          ObservabilityLabels.fromIdentity(_identity),
          ObservabilityLabels.fromIdentity(_identity),
        );
        expect(
          ObservabilityLabels.fromIdentity(_identity).hashCode,
          ObservabilityLabels.fromIdentity(_identity).hashCode,
        );
      });

      test('emit merges per-call labels but LPSM base always wins', () {
        final List<Map<String, String>> captured = <Map<String, String>>[];
        final ObservabilityContext context = ObservabilityContext.fromIdentity(
          _identity,
          sink: _CapturingSink(captured),
        );

        context.emit(
          'app.start',
          extra: <String, String>{'route': 'home', 'service': 'spoofed'},
        );

        expect(captured, hasLength(1));
        expect(captured.single['route'], 'home');
        // LPSM base overrides any per-call attempt to change identity labels.
        expect(captured.single['service'], 'service');
      });

      test('default sink is the held no-op transport', () {
        const ObservabilityContext context = ObservabilityContext(
          labels: ObservabilityLabels(
            landscape: 'lapras',
            platform: 'platform',
            service: 'service',
            module: 'app',
            version: '1.0.0',
          ),
        );
        expect(context.sink, isA<NoopSignalSink>());
        // Must not throw with no exporter wired.
        context.emit('app.noop');
      });
    },
  );

  group('E4 integration manifest (held pending accepted lib/dart/e2e sha)', () {
    test('frozen accepted flutter-base sha is recorded', () {
      expect(
        flutterBaseAcceptedSha,
        '891c5c9bad5c81b5d1011ac75143489b927cee94',
      );
    });

    test('integration is honestly held, not falsely complete', () {
      expect(e4IntegrationComplete, isFalse);
      expect(e4HeldPoints, isNotEmpty);
      expect(primaryHoldReason, contains('lib/dart/e2e'));
    });

    test('the observability wiring point stands live (not held)', () {
      final E4IntegrationPoint observability = e4IntegrationMap.firstWhere(
        (E4IntegrationPoint p) =>
            p.localBridge.contains('observability_wiring'),
      );
      expect(observability.held, isFalse);
    });

    test('every diene package point is held until e2e lands', () {
      final Iterable<E4IntegrationPoint> dieneEngine = e4IntegrationMap.where(
        (E4IntegrationPoint p) => p.dienePackage.contains('lib/dart/e2e'),
      );
      expect(dieneEngine, isNotEmpty);
      expect(dieneEngine.every((E4IntegrationPoint p) => p.held), isTrue);
    });
  });
}

final class _CapturingSink implements SignalSink {
  _CapturingSink(this._captured);

  final List<Map<String, String>> _captured;

  @override
  void recordSignal(String name, {required Map<String, String> labels}) {
    _captured.add(labels);
  }
}
