import 'dart:math';

import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:test/test.dart';

LpsmCoordinate _coordOf({
  String landscape = 'lapras',
  String platform = 'platform',
  String service = 'service',
  String module = 'core',
}) => LpsmCoordinate(
  landscape: landscape,
  platform: platform,
  service: service,
  module: module,
);

final LpsmCoordinate _coord = _coordOf();

// Scoped Doc-C cache keys (platform × landscape) — must match router.dart.
String _dc(LpsmCoordinate c) => 'docc.${c.platform}.${c.landscape}';
String _dcv(LpsmCoordinate c) => 'docc.version.${c.platform}.${c.landscape}';

RescueConfig _cfg({
  bool enabled = true,
  List<String> allowlist = const <String>[
    '.cluster.atomi.cloud',
    '.catalogs.atomi.cloud',
  ],
  List<String> catalogHosts = const <String>['fleet.catalogs.atomi.cloud'],
  Duration scanBudget = const Duration(seconds: 8),
  Duration perCandidateTimeout = const Duration(seconds: 3),
  Duration maxJitter = const Duration(milliseconds: 250),
}) => RescueConfig(
  enabled: enabled,
  issuer: Uri.parse('https://auth.atomi.cloud'),
  catalogHosts: catalogHosts,
  endpointSuffixAllowlist: allowlist,
  scanBudget: scanBudget,
  perCandidateTimeout: perCandidateTimeout,
  maxJitter: maxJitter,
);

RescueRouter _router(
  RescueStore store,
  HttpTransport transport, {
  RescueConfig? config,
  Future<void> Function(Duration)? sleep,
  int Function()? nowMs,
  Duration Function()? jitter,
  Random? random,
}) => RescueRouter(
  config: config ?? _cfg(),
  store: store,
  transport: transport,
  sleep: sleep ?? noSleep,
  nowMs: nowMs,
  jitter: jitter ?? noJitter,
  random: random,
);

void main() {
  test('issuer is the baked config issuer, never doc-sourced', () {
    final RescueRouter router = _router(
      FakeRescueStore(),
      FakeHttpTransport.byHost(const {}),
    );
    expect(router.bakedIssuer, Uri.parse('https://auth.atomi.cloud'));
  });

  group('allowlist enforcement', () {
    test('accepts baked suffix, rejects foreign host', () {
      final RescueRouter router = _router(
        FakeRescueStore(),
        FakeHttpTransport.byHost(const {}),
      );
      expect(
        router.isAllowed(Uri.parse('https://a.cluster.atomi.cloud')),
        isTrue,
      );
      expect(router.isAllowed(Uri.parse('https://evil.example.com')), isFalse);
    });

    test('a non-allowlisted Doc-C candidate is filtered out', () async {
      final DocC docC = DocC(
        version: 3,
        candidates: <String, List<String>>{
          _coord.key: <String>['https://evil.example.com'],
        },
      );
      final RescueRouter router = _router(
        FakeRescueStore(<String, String>{
          _dc(_coord): docC.encode(),
          _dcv(_coord): '3',
          'doca.version': '9',
        }),
        FakeHttpTransport.byHost(<String, TransportOutcome>{
          'evil.example.com': okJson(<String, Object?>{}),
        }),
      );
      expect(await router.rescue(_coord), isA<RescueUnavailable>());
    });

    test(
      'P1#1: a poisoned Doc A cannot redirect the Doc-C fetch off baked roots',
      () async {
        final FakeHttpTransport transport = FakeHttpTransport.byHost(
          <String, TransportOutcome>{
            'fleet.catalogs.atomi.cloud': okJson(<String, Object?>{
              'version': 5,
              'catalogHosts': <String>['evil.example.com'],
            }),
            'evil.example.com': okJson(
              DocC(
                version: 9,
                candidates: <String, List<String>>{
                  _coord.key: <String>['https://pwned.cluster.atomi.cloud'],
                },
              ).toJson(),
            ),
          },
        );
        final RescueRouter router = _router(
          FakeRescueStore(<String, String>{'doca.version': '1'}),
          transport,
        );

        final RescueOutcome outcome = await router.rescue(_coord);

        expect(outcome, isA<RescueUnavailable>());
        expect(
          transport.sent.any(
            (HttpRequest r) => r.url.host == 'evil.example.com',
          ),
          isFalse,
        );
      },
    );
  });

  test('disabled router stays dormant', () async {
    final RescueRouter router = _router(
      FakeRescueStore(),
      FakeHttpTransport.byHost(const {}),
      config: _cfg(enabled: false),
    );
    expect(await router.rescue(_coord), isA<RescueUnavailable>());
  });

  test(
    'monotonic versions: an older fetched Doc C never replaces the cache',
    () async {
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
          _dc(_coord): cached.encode(),
          _dcv(_coord): '10',
          'doca.version': '1',
        }),
        FakeHttpTransport.byHost(<String, TransportOutcome>{
          'fleet.catalogs.atomi.cloud': okJson(<String, Object?>{
            'version': 2,
            'catalogHosts': <String>['cat.catalogs.atomi.cloud'],
          }),
          'cat.catalogs.atomi.cloud': okJson(stale.toJson()),
          'c10.cluster.atomi.cloud': okJson(<String, Object?>{}),
          'c2.cluster.atomi.cloud': okJson(<String, Object?>{}),
        }),
      );

      final RescueOutcome outcome = await router.rescue(_coord);
      expect(outcome, isA<Rescued>());
      expect((outcome as Rescued).baseUrl.host, 'c10.cluster.atomi.cloud');
    },
  );

  test('P1#4: Doc-C cache is scoped per platform — a 2nd platform never reuses '
      "the 1st platform's catalog, even at the same Doc A version", () async {
    final LpsmCoordinate a = _coordOf(platform: 'plata');
    final LpsmCoordinate b = _coordOf(platform: 'platb');

    final FakeHttpTransport transport = FakeHttpTransport((HttpRequest req) {
      switch (req.url.host) {
        case 'a.cluster.atomi.cloud':
        case 'b.cluster.atomi.cloud':
          return okJson(<String, Object?>{}); // healthy probe
        case 'fleet.catalogs.atomi.cloud':
          return okJson(<String, Object?>{
            'version': 5, // fleet Doc A stays at v5 across both rescues
            'catalogHosts': <String>['cat.catalogs.atomi.cloud'],
          });
        case 'cat.catalogs.atomi.cloud':
          if (req.url.path == '/catalog/plata.json') {
            return okJson(
              DocC(
                version: 1,
                candidates: <String, List<String>>{
                  a.key: <String>['https://a.cluster.atomi.cloud'],
                },
              ).toJson(),
            );
          }
          if (req.url.path == '/catalog/platb.json') {
            return okJson(
              DocC(
                version: 1,
                candidates: <String, List<String>>{
                  b.key: <String>['https://b.cluster.atomi.cloud'],
                },
              ).toJson(),
            );
          }
          return networkFailure('unknown catalog path');
        default:
          return networkFailure('unmapped');
      }
    });
    final FakeRescueStore store = FakeRescueStore();
    final RescueRouter router = _router(store, transport);

    // Platform A rescues first and caches its own catalog (advancing Doc A → 5).
    final RescueOutcome oa = await router.rescue(a);
    // Platform B rescues while Doc A is unchanged at v5.
    final RescueOutcome ob = await router.rescue(b);

    expect((oa as Rescued).baseUrl.host, 'a.cluster.atomi.cloud');
    expect((ob as Rescued).baseUrl.host, 'b.cluster.atomi.cloud');
    // Each platform cached under its OWN scope key; no cross-reuse.
    expect(await store.read(_dc(a)), isNotNull);
    expect(await store.read(_dc(b)), isNotNull);
    expect(await store.read(_dc(a)), isNot(await store.read(_dc(b))));
  });

  test(
    'last-known-good is kept forever and used when no candidate is healthy',
    () async {
      final DocC docC = DocC(
        version: 4,
        candidates: <String, List<String>>{
          _coord.key: <String>['https://dead.cluster.atomi.cloud'],
        },
      );
      final RescueRouter router = _router(
        FakeRescueStore(<String, String>{
          _dc(_coord): docC.encode(),
          _dcv(_coord): '4',
          'doca.version': '9',
          'lastgood.${_coord.key}': 'https://good.cluster.atomi.cloud',
        }),
        FakeHttpTransport.byHost(<String, TransportOutcome>{
          'dead.cluster.atomi.cloud': networkFailure('down'),
        }),
      );

      final RescueOutcome outcome = await router.rescue(_coord);
      expect(outcome, isA<Rescued>());
      final Rescued rescued = outcome as Rescued;
      expect(rescued.fromLastKnownGood, isTrue);
      expect(rescued.baseUrl.host, 'good.cluster.atomi.cloud');
    },
  );

  test(
    'same-landscape only: a foreign-landscape key is never consulted',
    () async {
      final LpsmCoordinate foreign = _coordOf(landscape: 'pichu');
      final DocC docC = DocC(
        version: 7,
        candidates: <String, List<String>>{
          foreign.key: <String>['https://pichu.cluster.atomi.cloud'],
        },
      );
      final RescueRouter router = _router(
        FakeRescueStore(<String, String>{
          _dc(_coord): docC.encode(),
          _dcv(_coord): '7',
          'doca.version': '9',
        }),
        FakeHttpTransport.byHost(<String, TransportOutcome>{
          'pichu.cluster.atomi.cloud': okJson(<String, Object?>{}),
        }),
      );
      expect(await router.rescue(_coord), isA<RescueUnavailable>());
    },
  );

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
    expect(
      await router.probeHealthy(Uri.parse('https://primary.example.com')),
      isTrue,
    );
    await router.onPrimaryHealed(_coord);
    expect(await router.pinnedFor(_coord), isNull);
  });

  group('P1#2: jitter + strict budgets', () {
    test('production jitter is drawn from [0, maxJitter]', () {
      final RescueRouter router = _router(
        FakeRescueStore(),
        FakeHttpTransport.byHost(const {}),
        config: _cfg(maxJitter: const Duration(milliseconds: 200)),
        jitter: null,
        random: Random(1234),
      );
      for (var i = 0; i < 50; i++) {
        expect(router.nextJitter().inMilliseconds, inInclusiveRange(0, 200));
      }
    });

    test(
      'a hanging probe cannot exceed the GLOBAL scan budget (fail-closed)',
      () async {
        final DocC docC = DocC(
          version: 1,
          candidates: <String, List<String>>{
            _coord.key: <String>[
              for (var i = 0; i < 5; i++) 'https://c$i.cluster.atomi.cloud',
            ],
          },
        );
        final FakeClock clock = FakeClock();
        final HangingTransport transport = HangingTransport();
        final RescueRouter router = _router(
          FakeRescueStore(<String, String>{
            _dc(_coord): docC.encode(),
            _dcv(_coord): '1',
            'doca.version': '9',
          }),
          transport,
          config: _cfg(
            catalogHosts: const <String>[],
            scanBudget: const Duration(seconds: 8),
            perCandidateTimeout: const Duration(seconds: 3),
          ),
          sleep: clock.sleep,
          nowMs: clock.nowMs,
          jitter: noJitter,
        );

        final RescueOutcome outcome = await router.rescue(_coord);

        expect(outcome, isA<RescueUnavailable>());
        expect(clock.nowMs(), lessThanOrEqualTo(8000));
        expect(transport.sent.length, lessThan(5));
      },
    );

    test('perCandidateTimeout bounds a single hanging probe', () async {
      final DocC docC = DocC(
        version: 1,
        candidates: <String, List<String>>{
          _coord.key: <String>['https://only.cluster.atomi.cloud'],
        },
      );
      final FakeClock clock = FakeClock();
      final RescueRouter router = _router(
        FakeRescueStore(<String, String>{
          _dc(_coord): docC.encode(),
          _dcv(_coord): '1',
          'doca.version': '9',
        }),
        HangingTransport(),
        config: _cfg(
          catalogHosts: const <String>[],
          scanBudget: const Duration(seconds: 30),
          perCandidateTimeout: const Duration(seconds: 3),
        ),
        sleep: clock.sleep,
        nowMs: clock.nowMs,
        jitter: noJitter,
      );

      await router.rescue(_coord);
      expect(clock.nowMs(), 3000);
    });
  });
}
