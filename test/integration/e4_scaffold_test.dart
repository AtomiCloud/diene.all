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

  group('E4 integration manifest (diene surface integrated from pub.dev)', () {
    test('frozen accepted flutter-base sha is recorded', () {
      expect(
        flutterBaseAcceptedSha,
        '891c5c9bad5c81b5d1011ac75143489b927cee94',
      );
    });

    test('integration is complete: no point remains held', () {
      // The published diene packages landed via pub.dev (declared by W4 at
      // 15c8185), dissolving the original lib/dart/e2e await, so every point is
      // cleared.
      expect(e4IntegrationComplete, isTrue);
      expect(e4HeldPoints, isEmpty);
      expect(primaryHoldReason, contains('No hold remains'));
      expect(primaryHoldReason, contains('pub.dev'));
    });

    test('the observability wiring point stands live (not held)', () {
      final E4IntegrationPoint observability = e4IntegrationMap.firstWhere(
        (E4IntegrationPoint p) =>
            p.localBridge.contains('observability_wiring'),
      );
      expect(observability.held, isFalse);
    });

    test('every diene package point is cleared and names its pub.dev package',
        () {
      final Iterable<E4IntegrationPoint> dieneEngine = e4IntegrationMap.where(
        (E4IntegrationPoint p) => p.dienePackage.contains('diene_'),
      );
      expect(dieneEngine, hasLength(5));
      expect(dieneEngine.every((E4IntegrationPoint p) => !p.held), isTrue);
      expect(
        dieneEngine.every((E4IntegrationPoint p) =>
            p.dienePackage.contains('pub.dev') &&
            !p.dienePackage.contains('lib/dart/e2e')),
        isTrue,
      );
    });

    test('the auth transport swap is DONE; only the api swap remains owed', () {
      // The public-surface migration the user ruled in is complete: the local
      // AuthGateway / ExtraParamsSignIn seams are deleted and session/refresh
      // now drive the published diene_auth_engine AuthProvider directly, so the
      // auth-engine point no longer records an owed follow-on.
      final E4IntegrationPoint auth = e4IntegrationMap.singleWhere(
        (E4IntegrationPoint p) => p.dienePackage.contains('diene_auth_engine'),
      );
      expect(auth.note.contains('FOLLOW-ON OWED'), isFalse);
      expect(auth.note.contains('DONE'), isTrue);

      // The api-engine (retrofit fallback) swap is a separate node and is still
      // genuinely owed — it must stay RECORDED as owed, not merely omitted.
      final E4IntegrationPoint api = e4IntegrationMap.singleWhere(
        (E4IntegrationPoint p) => p.dienePackage.contains('diene_api_engine'),
      );
      expect(api.note.contains('FOLLOW-ON OWED'), isTrue);
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
