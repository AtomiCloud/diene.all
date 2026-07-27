// META TIER — subject = the TestHelper code (assert-the-asserter, contract
// parity, fixture/builder invariants). Run via `pls test:meta`.
import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:diene_auth_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final DateTime now = DateTime.utc(2026, 7, 21);

  group('assert-the-asserter: AuthExpect', () {
    test('ok passes on Success and throws on Failure', () {
      // Known-good
      expect(AuthExpect.ok(const Success<int>(1)), 1);
      // Known-bad
      expect(
        () => AuthExpect.ok(
          const Failure<int>(Problem(type: 't', title: 'x', status: 400)),
        ),
        throwsA(isA<AuthAssertionError>()),
      );
    });

    test('err passes on Failure and throws on Success', () {
      expect(
        AuthExpect.err(
          const Failure<int>(Problem(type: 't', title: 'x', status: 400)),
        ).status,
        400,
      );
      expect(
        () => AuthExpect.err(const Success<int>(1)),
        throwsA(isA<AuthAssertionError>()),
      );
    });

    test('errType matches the problem type and rejects a mismatch', () {
      const Result<int> failure = Failure<int>(
        Problem(type: 'urn:x', title: 'x', status: 400),
      );
      expect(AuthExpect.errType(failure, 'urn:x').type, 'urn:x');
      expect(
        () => AuthExpect.errType(failure, 'urn:y'),
        throwsA(isA<AuthAssertionError>()),
      );
    });

    test('some/none behave and fail on the opposite arm', () {
      expect(AuthExpect.some(const Some<int>(3)), 3);
      expect(
        () => AuthExpect.some(const None<int>()),
        throwsA(isA<AuthAssertionError>()),
      );
      AuthExpect.none(const None<int>());
      expect(
        () => AuthExpect.none(const Some<int>(3)),
        throwsA(isA<AuthAssertionError>()),
      );
    });

    test('phase / status pass on match and throw on mismatch', () {
      AuthExpect.phase(OnboardingPhase.ready, OnboardingPhase.ready);
      expect(
        () => AuthExpect.phase(OnboardingPhase.ready, OnboardingPhase.error),
        throwsA(isA<AuthAssertionError>()),
      );
      AuthExpect.status(const Problem(type: 't', title: 'x', status: 410), 410);
      expect(
        () => AuthExpect.status(
          const Problem(type: 't', title: 'x', status: 400),
          410,
        ),
        throwsA(isA<AuthAssertionError>()),
      );
    });
  });

  group('fixture/builder invariants: AuthFixtures', () {
    test('jwt payload decodes back to the supplied claims', () {
      final String token = AuthFixtures.jwt(<String, Object?>{'k': 'v'});
      expect(Claims.decode(token)['k'], 'v');
    });

    test('registeredJwt carries the exact registration claim', () {
      final ResourceKey key = AuthFixtures.resourceKey();
      expect(
        Claims.hasRegistration(
          Claims.decode(AuthFixtures.registeredJwt(key)),
          platform: key.platform,
          service: key.service,
        ),
        isTrue,
      );
    });

    test('unregisteredJwt omits the registration claim', () {
      final ResourceKey key = AuthFixtures.resourceKey();
      expect(
        Claims.hasRegistration(
          Claims.decode(AuthFixtures.unregisteredJwt(key)),
          platform: key.platform,
          service: key.service,
        ),
        isFalse,
      );
    });

    test('sessionTokens honours the family lifetimes', () {
      final SessionTokens tokens = AuthFixtures.sessionTokens(now: now);
      expect(tokens.accessExpiresAt.difference(now), TokenLifetimes.access);
      expect(tokens.refreshExpiresAt.difference(now), TokenLifetimes.refresh);
    });
  });

  group('contract parity: fakes honour their seam contracts', () {
    test('FakeAuth returns one terminal entry per requested key', () async {
      final ResourceKey key = AuthFixtures.resourceKey();
      final FakeAuth auth = FakeAuth(<Map<ResourceKey, Result<ResourceToken>>>[
        <ResourceKey, Result<ResourceToken>>{
          key: Success<ResourceToken>(
            AuthFixtures.resourceToken(now: now, jwtToken: 'j'),
          ),
        },
      ]);
      final Map<ResourceKey, Result<ResourceToken>> batch = await auth
          .fetchAllTokens(<ResourceKey>[key]);
      expect(batch.length, 1);
      expect(AuthExpect.ok(batch[key]!).token, 'j');
    });

    test('MemoryHomeClaimStore round-trips read/write/clear', () async {
      final MemoryHomeClaimStore store = MemoryHomeClaimStore();
      expect(await store.read(), isNull);
      await store.write('pichu');
      expect(await store.read(), 'pichu');
      await store.clear();
      expect(await store.read(), isNull);
    });

    test('FakeClipboardCarrierSource clears only on an exact match', () async {
      final FakeClipboardCarrierSource clip = FakeClipboardCarrierSource(
        '  x ',
      );
      await clip.clearIfEquals('y');
      expect(clip.cleared, isFalse);
      await clip.clearIfEquals('x');
      expect(clip.cleared, isTrue);
    });

    test(
      'FakeAuthProvider scripts sign-in / refresh / re-mint / tokens',
      () async {
        final ResourceKey key = AuthFixtures.resourceKey();
        final FakeAuthProvider provider = FakeAuthProvider(
          onSignIn: () => AuthFixtures.sessionTokens(now: now),
          onRefresh: (SessionTokens c) => AuthFixtures.sessionTokens(now: now),
          onReMint: (SessionTokens c) => AuthFixtures.sessionTokens(now: now),
          resourceTokens: <String, ResourceToken>{
            key.mapKey: AuthFixtures.resourceToken(now: now, jwtToken: 'j'),
          },
          idTokenValue: 'id',
          freshClaimTokenValue: 'fresh.claim.jwt',
        );

        final SessionTokens signedIn = await provider.signIn(
          extraParams: <String, String>{'one_time_token': 't'},
        );
        await provider.refresh(signedIn);
        await provider.reMintOnOpen(signedIn);
        await provider.signOut();

        expect(provider.signInCount, 1);
        expect(provider.refreshCount, 1);
        expect(provider.reMintCount, 1);
        expect(provider.signOutCount, 1);
        expect(provider.lastExtraParams['one_time_token'], 't');
        expect((await provider.resourceToken(key)).token, 'j');
        expect(await provider.idToken(), 'id');
        expect(await provider.freshClaimToken(), 'fresh.claim.jwt');
        expect(provider.freshClaimTokenCount, 1);
      },
    );

    test(
      'FakeAuthProvider throwOnSignIn surfaces the scripted error',
      () async {
        final FakeAuthProvider provider = FakeAuthProvider(
          throwOnSignIn: StateError('nope'),
        );
        await expectLater(provider.signIn(), throwsStateError);
      },
    );

    test('FakeAuth advances batches and records invalidation', () async {
      final ResourceKey key = AuthFixtures.resourceKey();
      final FakeAuth auth = FakeAuth(<Map<ResourceKey, Result<ResourceToken>>>[
        <ResourceKey, Result<ResourceToken>>{
          key: Success<ResourceToken>(
            AuthFixtures.resourceToken(now: now, jwtToken: 'a'),
          ),
        },
        <ResourceKey, Result<ResourceToken>>{
          key: Success<ResourceToken>(
            AuthFixtures.resourceToken(now: now, jwtToken: 'b'),
          ),
        },
      ]);
      await auth.fetchAllTokens(<ResourceKey>[key]); // batch 0
      final Result<ResourceToken> second = await auth.tokenFor(key); // batch 1
      auth.invalidate(key);
      auth.invalidateAll();
      expect(AuthExpect.ok(second).token, 'b');
      expect(auth.invalidated, <String>[key.mapKey]);
      expect(auth.invalidateAllCount, 1);
    });

    test(
      'FakeUserDirectory / FakeAppHandoffApi / referrer count calls',
      () async {
        final FakeUserDirectory dir = FakeUserDirectory(
          getStatus: 404,
          postStatus: 201,
        );
        expect(await dir.getUserMe(backendId: 'b', accessToken: 't'), 404);
        expect(
          await dir.postUser(backendId: 'b', accessToken: 't', idToken: 'i'),
          201,
        );
        expect(dir.getCount, 1);
        expect(dir.postCount, 1);

        final FakeAppHandoffApi api = FakeAppHandoffApi(
          result: const Success<RedeemResult>(
            RedeemResult(token: 't', email: 'e'),
          ),
        );
        expect(
          AuthExpect.ok(
            await api.redeem(
              nonce: 'n',
              device: const DeviceInfo(platform: 'ios'),
            ),
          ).token,
          't',
        );
        expect(api.redeemCount, 1);

        final FakeInstallReferrerSource ref = FakeInstallReferrerSource('r');
        expect(await ref.read(), 'r');
        await ref.markProcessed();
        expect(ref.processed, isTrue);
      },
    );

    test(
      'FakeLandscapeSelectorSource / FakeRegionPinger honour scripts',
      () async {
        final FakeLandscapeSelectorSource source = FakeLandscapeSelectorSource(
          doc: const LandscapeSelectorDoc(
            platform: 'p',
            tier: 't',
            landscapes: <LandscapeEntry>[
              LandscapeEntry(name: 'a', region: 'r'),
            ],
          ),
        );
        expect((await source.fetch()).landscapes.length, 1);
        expect(source.fetchCount, 1);

        final FakeRegionPinger pinger = FakeRegionPinger(<String, Duration?>{
          'a': const Duration(milliseconds: 5),
        });
        expect(
          await pinger.ping(const LandscapeEntry(name: 'a', region: 'r')),
          const Duration(milliseconds: 5),
        );
        expect(pinger.pinged, <String>['a']);
      },
    );
  });
}
