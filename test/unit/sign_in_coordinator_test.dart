import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:diene_auth_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final DateTime now = DateTime.utc(2026, 7, 21);
  final ResourceKey key = AuthFixtures.resourceKey();

  SessionController session({Object? throwOnSignIn}) => SessionController(
    provider: FakeAuthProvider(
      onSignIn: () => AuthFixtures.sessionTokens(now: now),
      throwOnSignIn: throwOnSignIn,
    ),
    now: () => now,
  );

  MultiBackendOnboarding onboarding() => MultiBackendOnboarding(
    registry: BackendRegistry(<RegisteredBackend>[
      RegisteredBackend(
        backendId: 'primary',
        resources: <ResourceKey>[key],
        onboardingResource: key,
      ),
    ]),
    auth: FakeAuth(<Map<ResourceKey, Result<ResourceToken>>>[
      <ResourceKey, Result<ResourceToken>>{
        key: Success<ResourceToken>(
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

  HomeClaimResolver resolver(MemoryHomeClaimStore store) => HomeClaimResolver(
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
    'cached home skips Doc B, logs in, onboards, resumes returnTo',
    () async {
      // Arrange
      final SignInCoordinator coordinator = SignInCoordinator(
        session: session(),
        homeResolver: resolver(MemoryHomeClaimStore('pichu')),
        onboarding: onboarding(),
      );

      // Act
      final Result<SignInResult> result = await coordinator.signIn(
        returnTo: Uri.parse('/secret?x=1'),
      );

      // Assert
      final SignInResult signIn = AuthExpect.ok(result);
      expect(signIn.home.kind, HomeResolutionKind.cached);
      expect(signIn.phases['primary'], isA<Success<OnboardingPhase>>());
      expect(signIn.continueTo.toString(), '/secret?x=1');
    },
  );

  test('absent home selects and commits the sign-up landscape', () async {
    // Arrange
    final MemoryHomeClaimStore store = MemoryHomeClaimStore();
    final SignInCoordinator coordinator = SignInCoordinator(
      session: session(),
      homeResolver: resolver(store),
      onboarding: onboarding(),
    );

    // Act
    final SignInResult signIn = AuthExpect.ok(await coordinator.signIn());

    // Assert
    expect(signIn.home.kind, HomeResolutionKind.selected);
    expect(signIn.home.landscape, 'lapras');
    expect(store.value, 'lapras'); // committed
  });

  test('a login failure aborts the flow', () async {
    // Arrange
    final SignInCoordinator coordinator = SignInCoordinator(
      session: session(throwOnSignIn: StateError('bad creds')),
      homeResolver: resolver(MemoryHomeClaimStore('pichu')),
      onboarding: onboarding(),
    );

    // Act + Assert
    expect(await coordinator.signIn(), isA<Failure<SignInResult>>());
  });

  test('an invalid returnTo yields no continuation', () async {
    // Arrange
    final SignInCoordinator coordinator = SignInCoordinator(
      session: session(),
      homeResolver: resolver(MemoryHomeClaimStore('pichu')),
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
