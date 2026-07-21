import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:test/test.dart';

final LpsmCoordinate _coord = LpsmCoordinate(
  landscape: 'lapras',
  platform: 'platform',
  service: 'service',
  module: 'core',
);

RescueConfig _cfg({
  bool enabled = true,
  List<String> allowlist = const <String>['.cluster.atomi.cloud'],
  List<String> catalogHosts = const <String>['r2.example.com'],
}) =>
    RescueConfig(
      enabled: enabled,
      issuer: Uri.parse('https://auth.atomi.cloud'),
      catalogHosts: catalogHosts,
      endpointSuffixAllowlist: allowlist,
    );

RescueRouter _router(
  RescueStore store,
  HttpTransport transport, {
  RescueConfig? config,
}) =>
    RescueRouter(
      config: config ?? _cfg(),
      store: store,
      transport: transport,
      sleep: noSleep,
      jitter: noJitter,
    );

void main() {
  test('issuer is the baked config issuer, never doc-sourced', () {
    final RescueRouter router =
        _router(FakeRescueStore(), FakeHttpTransport.byHost(const {}));
    expect(router.bakedIssuer, Uri.parse('https://auth.atomi.cloud'));
  });

  group('allowlist enforcement', () {
    test('accepts baked suffix, rejects foreign host', () {
      final RescueRouter router =
          _router(FakeRescueStore(), FakeHttpTransport.byHost(const {}));
      expect(
          router.isAllowed(Uri.parse('https://a.cluster.atomi.cloud')), isTrue);
      expect(router.isAllowed(Uri.parse('https://evil.example.com')), isFalse);
    });

    test('a non-allowlisted candidate is filtered out of a rescue', () async {
      // Arrange: doc offers only a foreign host; no last-known-good.
      final DocC docC = DocC(
        version: 3,
        candidates: <String, List<String>>{
          _coord.key: <String>['https://evil.example.com'],
        },
      );
      final RescueRouter router = _router(
        FakeRescueStore(<String, String>{
          'docc': docC.encode(),
          'docc.version': '3',
          'doca.version': '9',
        }),
        FakeHttpTransport.byHost(<String, TransportOutcome>{
          'evil.example.com': okJson(<String, Object?>{}),
        }),
      );

      // Act
      final RescueOutcome outcome = await router.rescue(_coord);

      // Assert
      expect(outcome, isA<RescueUnavailable>());
    });
  });

  test('disabled router stays dormant', () async {
    final RescueRouter router = _router(
      FakeRescueStore(),
      FakeHttpTransport.byHost(const {}),
      config: _cfg(enabled: false),
    );
    expect(await router.rescue(_coord), isA<RescueUnavailable>());
  });

  test('monotonic versions: an older fetched doc never replaces the cache',
      () async {
    // Arrange: cache is v10 with candidate C10; the fetchable doc is v2 (older).
    final DocC cached = DocC(
      version: 10,
      candidates: <String, List<String>>{
        _coord.key: <String>['https://c10.cluster.atomi.cloud'],
      },
    );
    final DocC stale = DocC(
      version: 2,
      candidates: <String, List<String>>{
        _coord.key: <String>['https://c2.cluster.atomi.cloud'],
      },
    );
    final RescueRouter router = _router(
      FakeRescueStore(<String, String>{
        'docc': cached.encode(),
        'docc.version': '10',
        'doca.version': '1',
      }),
      FakeHttpTransport.byHost(<String, TransportOutcome>{
        // Doc A refresh advertises the catalog host and a newer Doc A version…
        'r2.example.com': okJson(<String, Object?>{
          'version': 2,
          'catalogHosts': <String>['catalog.example.com'],
        }),
        // …but the Doc C it serves is OLDER than the cache and must be rejected.
        'catalog.example.com': okJson(stale.toJson()),
        'c10.cluster.atomi.cloud': okJson(<String, Object?>{}),
        'c2.cluster.atomi.cloud': okJson(<String, Object?>{}),
      }),
    );

    // Act
    final RescueOutcome outcome = await router.rescue(_coord);

    // Assert: the v10 cache candidate is used, not the stale v2 one.
    expect(outcome, isA<Rescued>());
    expect((outcome as Rescued).baseUrl.host, 'c10.cluster.atomi.cloud');
  });

  test('last-known-good is kept forever and used when no candidate is healthy',
      () async {
    // Arrange: a pinned/last-good address exists; every candidate is down.
    final DocC docC = DocC(
      version: 4,
      candidates: <String, List<String>>{
        _coord.key: <String>['https://dead.cluster.atomi.cloud'],
      },
    );
    final RescueRouter router = _router(
      FakeRescueStore(<String, String>{
        'docc': docC.encode(),
        'docc.version': '4',
        'doca.version': '9',
        'lastgood.${_coord.key}': 'https://good.cluster.atomi.cloud',
      }),
      FakeHttpTransport.byHost(<String, TransportOutcome>{
        'dead.cluster.atomi.cloud': networkFailure('down'),
        'r2.example.com': networkFailure('doc host down'),
      }),
    );

    // Act
    final RescueOutcome outcome = await router.rescue(_coord);

    // Assert
    expect(outcome, isA<Rescued>());
    final Rescued rescued = outcome as Rescued;
    expect(rescued.fromLastKnownGood, isTrue);
    expect(rescued.baseUrl.host, 'good.cluster.atomi.cloud');
  });

  test('same-landscape only: a foreign-landscape key is never consulted',
      () async {
    // Arrange: doc has candidates ONLY under a different landscape's key.
    final LpsmCoordinate foreign = LpsmCoordinate(
      landscape: 'pichu',
      platform: 'platform',
      service: 'service',
      module: 'core',
    );
    final DocC docC = DocC(
      version: 7,
      candidates: <String, List<String>>{
        foreign.key: <String>['https://pichu.cluster.atomi.cloud'],
      },
    );
    final RescueRouter router = _router(
      FakeRescueStore(<String, String>{
        'docc': docC.encode(),
        'docc.version': '7',
        'doca.version': '9',
      }),
      FakeHttpTransport.byHost(<String, TransportOutcome>{
        'pichu.cluster.atomi.cloud': okJson(<String, Object?>{}),
        'r2.example.com': networkFailure('doc host down'),
      }),
    );

    // Act: rescuing the lapras coordinate must NOT reach the pichu candidate.
    final RescueOutcome outcome = await router.rescue(_coord);

    // Assert
    expect(outcome, isA<RescueUnavailable>());
  });

  test('pin can be cleared once the primary heals', () async {
    final FakeRescueStore store = FakeRescueStore(<String, String>{
      'pin.${_coord.key}': 'https://good.cluster.atomi.cloud',
    });
    final RescueRouter router = _router(
      store,
      FakeHttpTransport.byHost(<String, TransportOutcome>{
        'primary.example.com': okJson(<String, Object?>{}),
      }),
    );

    // Primary probes healthy → heal.
    expect(await router.probeHealthy(Uri.parse('https://primary.example.com')),
        isTrue);
    await router.onPrimaryHealed(_coord);
    expect(await router.pinnedFor(_coord), isNull);
  });
}
