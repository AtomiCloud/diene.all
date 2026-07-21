import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:diene_auth_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final DateTime now = DateTime.utc(2026, 7, 21);
  final ResourceKey key = AuthFixtures.resourceKey();

  SessionController session({Object? throwOnSignIn}) => SessionController(
    provider: FakeAuthProvider(
      onSignIn: () => AuthFixtures.sessionTokens(now: now),
      onReMint: (SessionTokens current) => AuthFixtures.sessionTokens(now: now),
      throwOnSignIn: throwOnSignIn,
    ),
    now: () => now,
  );

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
                ? const Failure<ResourceToken>(
                    Problem(type: 't', title: 'onboarding down', status: 503),
                  )
                : Success<ResourceToken>(
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

  // A claim reader that returns the successive authoritative-claim reads:
  // [pre-login, immediate-post-login, post-OnboardSync]. Clamps to the last.
  HomeClaimReader seqReader(List<String?> values) {
    int i = 0;
    return () async {
      final String? value = values[i < values.length ? i : values.length - 1];
      i += 1;
      return value;
    };
  }

  HomeClaimResolver resolver({
    required HomeClaimReader claimReader,
    MemoryHomeClaimStore? store,
  }) => HomeClaimResolver(
    claimReader: claimReader,
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

  test(
    'returning user: authoritative claim routes home, resumes returnTo',
    () async {
      // Arrange — claim present on every read.
      final SignInCoordinator coordinator = SignInCoordinator(
        session: session(),
        homeResolver: resolver(claimReader: () async => 'pichu'),
        onboarding: onboarding(),
      );

      // Act
      final SignInResult signIn = AuthExpect.ok(
        await coordinator.signIn(returnTo: Uri.parse('/secret?x=1')),
      );

      // Assert
      expect(signIn.home.kind, HomeResolutionKind.fromClaim);
      expect(signIn.home.landscape, 'pichu');
      expect(signIn.phases['primary'], isA<Success<OnboardingPhase>>());
      expect(signIn.continueTo.toString(), '/secret?x=1');
    },
  );

  test(
    'sign-up: confirms the post-OnboardSync claim from a fresh JWT',
    () async {
      // Arrange — absent pre/post-login, present only after onboarding.
      final MemoryHomeClaimStore store = MemoryHomeClaimStore();
      final SignInCoordinator coordinator = SignInCoordinator(
        session: session(),
        homeResolver: resolver(
          claimReader: seqReader(<String?>[null, null, 'lapras']),
          store: store,
        ),
        onboarding: onboarding(),
      );

      // Act
      final SignInResult signIn = AuthExpect.ok(await coordinator.signIn());

      // Assert — home comes from the confirmed JWT, and the mirror matches it.
      expect(signIn.home.kind, HomeResolutionKind.fromClaim);
      expect(signIn.home.landscape, 'lapras');
      expect(store.value, 'lapras');
    },
  );

  test(
    'sign-up: a differing OnboardSync claim overrides the selection',
    () async {
      // Arrange — Doc B picks lapras, but OnboardSync wrote pichu.
      final MemoryHomeClaimStore store = MemoryHomeClaimStore();
      final SignInCoordinator coordinator = SignInCoordinator(
        session: session(),
        homeResolver: resolver(
          claimReader: seqReader(<String?>[null, null, 'pichu']),
          store: store,
        ),
        onboarding: onboarding(),
      );

      // Act
      final SignInResult signIn = AuthExpect.ok(await coordinator.signIn());

      // Assert — the JWT value wins; the selection (lapras) is never persisted.
      expect(signIn.home.kind, HomeResolutionKind.fromClaim);
      expect(signIn.home.landscape, 'pichu');
      expect(store.value, 'pichu');
    },
  );

  test(
    'sign-up: still-missing claim errors and does NOT mirror the selection',
    () async {
      // Arrange — the claim never surfaces, even after onboarding.
      final MemoryHomeClaimStore store = MemoryHomeClaimStore();
      final SignInCoordinator coordinator = SignInCoordinator(
        session: session(),
        homeResolver: resolver(
          claimReader: seqReader(<String?>[null, null, null]),
          store: store,
        ),
        onboarding: onboarding(),
      );

      // Act
      final Result<SignInResult> result = await coordinator.signIn();

      // Assert — explicit unconfirmed error, no mirrored selection.
      expect(
        AuthExpect.err(result).type,
        'urn:diene:problem:home-claim-unconfirmed',
      );
      expect(store.value, isNull);
    },
  );

  test('sign-up: an onboarding error aborts without mirroring', () async {
    // Arrange — onboarding fails; no home claim can exist.
    final MemoryHomeClaimStore store = MemoryHomeClaimStore();
    final SignInCoordinator coordinator = SignInCoordinator(
      session: session(),
      homeResolver: resolver(
        claimReader: seqReader(<String?>[null, null]),
        store: store,
      ),
      onboarding: onboarding(fail: true),
    );

    // Act
    final Result<SignInResult> result = await coordinator.signIn();

    // Assert — the onboarding failure surfaces; nothing is mirrored.
    expect(result, isA<Failure<SignInResult>>());
    expect(store.value, isNull);
  });

  test('a login failure aborts the flow', () async {
    // Arrange
    final SignInCoordinator coordinator = SignInCoordinator(
      session: session(throwOnSignIn: StateError('bad creds')),
      homeResolver: resolver(claimReader: () async => 'pichu'),
      onboarding: onboarding(),
    );

    // Act + Assert
    expect(await coordinator.signIn(), isA<Failure<SignInResult>>());
  });

  test('an invalid returnTo yields no continuation', () async {
    // Arrange
    final SignInCoordinator coordinator = SignInCoordinator(
      session: session(),
      homeResolver: resolver(claimReader: () async => 'pichu'),
      onboarding: onboarding(),
    );

    // Act
    final SignInResult signIn = AuthExpect.ok(
      await coordinator.signIn(returnTo: Uri.parse('https://evil.example/x')),
    );

    // Assert
    expect(signIn.continueTo, isNull);
  });
}
