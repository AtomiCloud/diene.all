/// META TIER — the subject here is the shipped TestHelper itself, not the engine.
///
/// The inherited meta suite exercised only `FakeHttpTransport`, leaving
/// `HangingTransport`, `FakeAuth`, `FakeRescueStore`, `FakeClock`, `noJitter` and
/// `noSleep` at 4/41 lines — all of them PUBLIC exports that consumers build their
/// own tests on. A fake that is itself untested is a silent way to hand consumers
/// a broken assertion, so each one is shown doing the exact thing its doc comment
/// promises, and where it can fail closed, shown failing closed.
///
/// Coverage is raised by ADDING real assertions over shipped code, never by a
/// pragma, a threshold change or a deleted test.
library;

import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

/// A `ResourceKey` for `resourceName`, holding the other three LPSM labels
/// fixed. `ResourceKey` validates every component as a lowercase DNS label and
/// is NOT const-constructible, so tests build it through this helper rather than
/// repeating four named arguments (and rather than inventing a URL-shaped key —
/// the canonical map key is `platform/landscape/service/resourceName`).
ResourceKey _key(String resourceName) => ResourceKey(
  platform: 'platform',
  landscape: 'raichu',
  service: 'service',
  resourceName: resourceName,
);

/// The map key `FakeAuth` looks up for [resourceName].
String _mapKey(String resourceName) => _key(resourceName).mapKey;

void main() {
  const LpsmCoordinate coordinate = LpsmCoordinate(
    landscape: 'raichu',
    platform: 'diene',
    service: 'api',
    module: 'core',
  );

  group('FakeHttpTransport records and scripts', () {
    test('records every request in order and counts them', () async {
      final FakeHttpTransport t = FakeHttpTransport(
        (HttpRequest _) => okJson(<String, Object?>{'ok': true}),
      );
      await t.send(
        HttpRequest(method: HttpMethod.get, url: Uri.parse('https://a.test/1')),
      );
      await t.send(
        HttpRequest(
          method: HttpMethod.post,
          url: Uri.parse('https://a.test/2'),
        ),
      );

      expect(t.callCount, 2);
      expect(t.sent.map((HttpRequest r) => r.url.path), <String>['/1', '/2']);
      expect(t.sent.first.method, HttpMethod.get);
      expect(t.sent.last.method, HttpMethod.post);
    });

    test(
      'sequence replays one outcome per call, then repeats the last',
      () async {
        final FakeHttpTransport t = FakeHttpTransport.sequence(
          <TransportOutcome>[
            networkFailure('first'),
            okJson(<String, Object?>{'n': 2}),
          ],
        );
        final HttpRequest req = HttpRequest(
          method: HttpMethod.get,
          url: Uri.parse('https://a.test/x'),
        );

        expect(await t.send(req), isA<NetworkFailure>());
        expect(await t.send(req), isA<Received>());
        // The documented behaviour is that the LAST outcome repeats rather than
        // the list overrunning — a consumer relying on that must not get a throw.
        expect(await t.send(req), isA<Received>());
        expect(t.callCount, 3);
      },
    );

    test('byHost routes on host and falls back to orElse', () async {
      final FakeHttpTransport t = FakeHttpTransport.byHost(
        <String, TransportOutcome>{
          'primary.test': okJson(<String, Object?>{'via': 'primary'}),
        },
      );

      expect(
        await t.send(
          HttpRequest(
            method: HttpMethod.get,
            url: Uri.parse('https://primary.test/p'),
          ),
        ),
        isA<Received>(),
      );
      // An unmapped host must fail rather than silently succeed, or a routing
      // test could pass without the route existing.
      expect(
        await t.send(
          HttpRequest(
            method: HttpMethod.get,
            url: Uri.parse('https://other.test/p'),
          ),
        ),
        isA<NetworkFailure>(),
      );
    });
  });

  group('HangingTransport never completes', () {
    test('records the request but its future does not resolve', () async {
      final HangingTransport t = HangingTransport();
      final Future<TransportOutcome> pending = t.send(
        HttpRequest(method: HttpMethod.get, url: Uri.parse('https://h.test/')),
      );

      // The whole point of this fake is that a budget test can prove a hang is
      // bounded. If it ever completed, those tests would pass vacuously.
      bool settled = false;
      pending.then((_) => settled = true).ignore();
      await Future<void>.delayed(Duration.zero);

      expect(settled, isFalse);
      expect(t.sent, hasLength(1));
      expect(t.sent.single.url.host, 'h.test');
    });
  });

  group('FakeAuth resolves per resource and fails closed', () {
    test('returns a token for a known resource key', () async {
      final FakeAuth auth = FakeAuth(<String, String>{
        _mapKey('core'): 'tok-core',
      });
      final ResourceKey key = _key('core');

      final Result<ResourceToken> result = await auth.tokenFor(key);

      expect(expectOk(result).token, 'tok-core');
      expect(auth.queried, <String>[key.mapKey]);
    });

    test('an UNKNOWN key fails closed with a 401 Problem', () async {
      final FakeAuth auth = FakeAuth(const <String, String>{});

      final Result<ResourceToken> result = await auth.tokenFor(_key('absent'));

      // Fail-closed is the property the engine's token path depends on; a fake
      // that returned Ok here would hide a real auth bug in every consumer.
      final Problem problem = expectErr(result);
      expect(problem.status, 401);
      expect(problem.detail, contains('absent'));
    });

    test(
      'queried records every key IN ORDER, so bleed is assertable',
      () async {
        final FakeAuth auth = FakeAuth(<String, String>{
          _mapKey('a'): 'tok-a',
          _mapKey('b'): 'tok-b',
        });

        await auth.tokenFor(_key('b'));
        await auth.tokenFor(_key('a'));

        expect(auth.queried, <String>[_mapKey('b'), _mapKey('a')]);
      },
    );

    test('fetchAllTokens resolves each key independently', () async {
      final FakeAuth auth = FakeAuth(<String, String>{_mapKey('a'): 'tok-a'});

      final Map<ResourceKey, Result<ResourceToken>> all = await auth
          .fetchAllTokens(<ResourceKey>[_key('a'), _key('missing')]);

      expect(all, hasLength(2));
      // Looked up by a FRESH instance on purpose: ResourceKey defines == and
      // hashCode over (mapKey, domain), so a consumer keying a map by it must
      // get a hit. If that ever regressed, this would fail rather than a
      // consumer's own suite failing mysteriously.
      expect(expectOk(all[_key('a')]!).token, 'tok-a');
      expect(expectErr(all[_key('missing')]!).status, 401);
    });

    test('the invalidate seams are callable no-ops', () {
      final FakeAuth auth = FakeAuth(const <String, String>{});

      // They exist to satisfy the IAuth seam. Asserting they do not throw keeps
      // the production-only dead-code pass honest about them.
      expect(auth.invalidateAll, returnsNormally);
      expect(() => auth.invalidate(_key('a')), returnsNormally);
    });

    test('an explicit expiry is carried onto the token', () async {
      final DateTime expiry = DateTime.utc(2030, 5, 6);
      final FakeAuth auth = FakeAuth(<String, String>{
        _mapKey('a'): 'tok',
      }, expiresAt: expiry);

      final Result<ResourceToken> result = await auth.tokenFor(_key('a'));

      expect(expectOk(result).expiresAt, expiry);
    });
  });

  group('FakeRescueStore logs writes over a real in-memory store', () {
    test('write is recorded AND actually stored', () async {
      final FakeRescueStore store = FakeRescueStore();

      await store.write('pin.raichu', 'https://rescue.test');

      // Both halves matter: a log without a real write would let a pin test pass
      // while nothing was persisted.
      expect(store.writes, <String>['pin.raichu']);
      expect(await store.read('pin.raichu'), 'https://rescue.test');
    });

    test('a seed is readable and delete removes the entry', () async {
      final FakeRescueStore store = FakeRescueStore(<String, String>{
        'seeded': 'value',
      });

      expect(await store.read('seeded'), 'value');
      await store.delete('seeded');
      expect(await store.read('seeded'), isNull);
      // A delete is not a write, so the log must not grow.
      expect(store.writes, isEmpty);
    });

    test('an absent key reads null rather than throwing', () async {
      final FakeRescueStore store = FakeRescueStore();
      expect(await store.read('nope'), isNull);
    });
  });

  group('FakeClock is monotonic and advances deterministically', () {
    test('starts at zero by default and advances explicitly', () {
      final FakeClock clock = FakeClock();

      expect(clock.nowMs(), 0);
      clock.advance(const Duration(milliseconds: 250));
      expect(clock.nowMs(), 250);
      clock.advance(const Duration(seconds: 1));
      expect(clock.nowMs(), 1250);
    });

    test('honours an explicit start and never goes backwards', () {
      final FakeClock clock = FakeClock(500);
      final int before = clock.nowMs();

      clock.advance(Duration.zero);

      expect(clock.nowMs(), greaterThanOrEqualTo(before));
      expect(clock.nowMs(), 500);
    });

    test('sleep advances the clock and completes immediately', () async {
      final FakeClock clock = FakeClock();

      await clock.sleep(const Duration(seconds: 8));

      // This is what lets budget tests exercise real timing math with no
      // wall-clock wait; if sleep did not advance, those tests would be vacuous.
      expect(clock.nowMs(), 8000);
    });
  });

  group('deterministic scan helpers', () {
    test('noJitter is exactly zero', () {
      expect(noJitter(), Duration.zero);
    });

    test(
      'noSleep completes without advancing wall clock expectations',
      () async {
        await expectLater(noSleep(const Duration(hours: 1)), completes);
      },
    );
  });

  group('the fakes compose into a working engine', () {
    test('a rescue router built entirely from fakes stays dormant', () async {
      final RescueRouter router = RescueRouter(
        config: RescueConfig(
          enabled: false,
          issuer: Uri.parse('https://auth.test'),
          catalogHosts: const <String>['https://seed.test'],
          endpointSuffixAllowlist: const <String>['.test'],
        ),
        store: FakeRescueStore(),
        transport: FakeHttpTransport((HttpRequest _) => networkFailure()),
        sleep: noSleep,
        jitter: noJitter,
        nowMs: FakeClock().nowMs,
      );

      // The helper set is only useful if it assembles the real type; this is the
      // parity claim the meta tier exists to make.
      expect(await router.rescue(coordinate), isA<RescueUnavailable>());
      expect(router.bakedIssuer, Uri.parse('https://auth.test'));
    });
  });
}
