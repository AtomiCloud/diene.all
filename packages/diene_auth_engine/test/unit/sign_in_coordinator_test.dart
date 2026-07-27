import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:diene_auth_engine/test_helper.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final DateTime now = DateTime.utc(2026, 7, 21);
  final ResourceKey key = AuthFixtures.resourceKey();

  // JWT bytes for the stored (pre/post-login) token and the force-fresh token.
  String jwtWithHome(String home) =>
      AuthFixtures.jwt(<String, Object?>{Claims.homeLandscape: home});
  final String staleNoHome = AuthFixtures.jwt(<String, Object?>{'sub': 'u1'});

  MultiBackendOnboarding onboarding({bool fail = false}) =>
      MultiBackendOnboarding(
        registry: BackendRegistry(<RegisteredBackend>[
          RegisteredBackend(
            backendId: 'primary',
            resources: <ResourceKey>[key],
            onboardingResource: key,
          ),
        ]),
        auth: FakeAuth(<Map<ResourceKey, Result<ResourceToken>>>[
          <ResourceKey, Result<ResourceToken>>{
            key: fail
                ? const Err<ResourceToken>(
                    Problem(type: 't', title: 'onboarding down', status: 503),
                  )
                : Ok<ResourceToken>(
                    AuthFixtures.resourceToken(
                      now: now,
                      jwtToken: AuthFixtures.registeredJwt(key),
                    ),
                  ),
          },
        ]),
        directory: FakeUserDirectory(),
        idToken: () async => 'id',
      );

  // Wires the REAL coordinator over one FakeAuthProvider whose stored `idToken`
  // (the pre/post-login authoritative read) is DISTINCT from its force-fresh
  // `freshClaimToken` (the post-OnboardSync confirmation). The home readers are
  // bound to those exact provider methods — not a free-running sequence.
  ({
    SignInCoordinator coordinator,
    FakeAuthProvider provider,
    MemoryHomeClaimStore store,
  })
  build({
    String? storedIdToken,
    String? freshClaim,
    bool onboardingFail = false,
    Object? throwOnSignIn,
  }) {
    final FakeAuthProvider provider = FakeAuthProvider(
      onSignIn: () => AuthFixtures.sessionTokens(now: now),
      idTokenValue: storedIdToken,
      freshClaimTokenValue: freshClaim,
      throwOnSignIn: throwOnSignIn,
    );
    final MemoryHomeClaimStore store = MemoryHomeClaimStore();
    final HomeClaimResolver homeResolver = HomeClaimResolver(
      claimReader: jwtHomeClaimReader(provider.idToken),
      forcedClaimReader: jwtHomeClaimReader(provider.freshClaimToken),
      store: store,
      selector: LandscapeSelectorClient(
        source: FakeLandscapeSelectorSource(
          doc: const LandscapeSelectorDoc(
            platform: 'lithium',
            tier: 'prod',
            landscapes: <LandscapeEntry>[
              LandscapeEntry(name: 'lapras', region: 'sg'),
            ],
          ),
        ),
        pinger: FakeRegionPinger(<String, Duration?>{
          'lapras': const Duration(milliseconds: 10),
        }),
      ),
    );
    return (
      coordinator: SignInCoordinator(
        session: SessionController(provider: provider, now: () => now),
        homeResolver: homeResolver,
        onboarding: onboarding(fail: onboardingFail),
      ),
      provider: provider,
      store: store,
    );
  }

  test(
    'returning user: stored JWT claim routes home, resumes returnTo',
    () async {
      // Arrange — the stored token already carries home_landscape.
      final wired = build(storedIdToken: jwtWithHome('pichu'));

      // Act
      final SignInResult signIn = AuthExpect.ok(
        await wired.coordinator.signIn(returnTo: Uri.parse('/secret?x=1')),
      );

      // Assert — no forced refresh needed on the fast path.
      expect(signIn.home.kind, HomeResolutionKind.fromClaim);
      expect(signIn.home.landscape, 'pichu');
      expect(signIn.continueTo.toString(), '/secret?x=1');
      expect(wired.provider.freshClaimTokenCount, 0);
      expect(wired.store.value, 'pichu');
    },
  );

  test(
    'sign-up: confirms from the FORCE-FRESH token, not the stale stored one',
    () async {
      // Arrange — stored token lacks the claim; only the force-fresh token has it.
      final wired = build(
        storedIdToken: staleNoHome,
        freshClaim: jwtWithHome('lapras'),
      );

      // Act
      final SignInResult signIn = AuthExpect.ok(
        await wired.coordinator.signIn(),
      );

      // Assert — the claim came from freshClaimToken (stale read would 409).
      expect(signIn.home.kind, HomeResolutionKind.fromClaim);
      expect(signIn.home.landscape, 'lapras');
      expect(wired.store.value, 'lapras');
      expect(wired.provider.freshClaimTokenCount, 1);
    },
  );

  test(
    'sign-up: a differing OnboardSync claim overrides the Doc B selection',
    () async {
      // Arrange — Doc B picks lapras, but the fresh token says pichu.
      final wired = build(
        storedIdToken: staleNoHome,
        freshClaim: jwtWithHome('pichu'),
      );

      // Act
      final SignInResult signIn = AuthExpect.ok(
        await wired.coordinator.signIn(),
      );

      // Assert — the fresh JWT wins; the selection is never persisted.
      expect(signIn.home.landscape, 'pichu');
      expect(wired.store.value, 'pichu');
    },
  );

  test(
    'sign-up: a fresh token still lacking the claim errors without mirroring',
    () async {
      // Arrange — the force-fresh token carries no home_landscape.
      final wired = build(storedIdToken: staleNoHome, freshClaim: staleNoHome);

      // Act
      final Result<SignInResult> result = await wired.coordinator.signIn();

      // Assert
      expect(
        AuthExpect.err(result).type,
        'urn:diene:problem:home-claim-unconfirmed',
      );
      expect(wired.store.value, isNull);
      expect(wired.provider.freshClaimTokenCount, 1);
    },
  );

  test('sign-up: a null fresh token fails closed without mirroring', () async {
    // Arrange — the adapter could not guarantee a fresh token.
    final wired = build(storedIdToken: staleNoHome, freshClaim: null);

    // Act
    final Result<SignInResult> result = await wired.coordinator.signIn();

    // Assert
    expect(
      AuthExpect.err(result).type,
      'urn:diene:problem:home-claim-unconfirmed',
    );
    expect(wired.store.value, isNull);
  });

  test(
    'sign-up: an onboarding error aborts without mirroring or refreshing',
    () async {
      // Arrange
      final wired = build(
        storedIdToken: staleNoHome,
        freshClaim: jwtWithHome('lapras'),
        onboardingFail: true,
      );

      // Act
      final Result<SignInResult> result = await wired.coordinator.signIn();

      // Assert — onboarding failure surfaces; no confirmation, no mirror.
      expect(result, isA<Err<SignInResult>>());
      expect(wired.store.value, isNull);
      expect(wired.provider.freshClaimTokenCount, 0);
    },
  );

  test('a login failure aborts the flow', () async {
    // Arrange
    final wired = build(
      storedIdToken: jwtWithHome('pichu'),
      throwOnSignIn: StateError('bad creds'),
    );

    // Act + Assert
    expect(await wired.coordinator.signIn(), isA<Err<SignInResult>>());
  });

  test('an invalid returnTo yields no continuation', () async {
    // Arrange
    final wired = build(storedIdToken: jwtWithHome('pichu'));

    // Act
    final SignInResult signIn = AuthExpect.ok(
      await wired.coordinator.signIn(
        returnTo: Uri.parse('https://evil.example/x'),
      ),
    );

    // Assert
    expect(signIn.continueTo, isNull);
  });
}
