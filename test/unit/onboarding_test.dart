import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:diene_auth_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final DateTime now = DateTime.utc(2026, 7, 21);
  final ResourceKey key = AuthFixtures.resourceKey();

  RegisteredBackend backend({String? appClaim}) => RegisteredBackend(
    backendId: 'primary',
    resources: <ResourceKey>[key],
    onboardingResource: key,
    appOnboardingClaim: appClaim,
  );

  Map<ResourceKey, Result<ResourceToken>> registered({
    Map<String, Object?> extra = const <String, Object?>{},
  }) => <ResourceKey, Result<ResourceToken>>{
    key: Success<ResourceToken>(
      AuthFixtures.resourceToken(
        now: now,
        jwtToken: AuthFixtures.registeredJwt(key, extra: extra),
      ),
    ),
  };

  Map<ResourceKey, Result<ResourceToken>> unregistered() =>
      <ResourceKey, Result<ResourceToken>>{
        key: Success<ResourceToken>(
          AuthFixtures.resourceToken(
            now: now,
            jwtToken: AuthFixtures.unregisteredJwt(key),
          ),
        ),
      };

  OnboardingMachine machine(
    FakeAuth auth, {
    FakeUserDirectory? directory,
    RegisteredBackend? b,
  }) => OnboardingMachine(
    backend: b ?? backend(),
    auth: auth,
    directory: directory ?? FakeUserDirectory(),
    idToken: () async => 'id-token',
  );

  test('all resources registered → ready without a /User call', () async {
    // Arrange
    final FakeUserDirectory directory = FakeUserDirectory();
    final OnboardingMachine m = machine(
      FakeAuth(<Map<ResourceKey, Result<ResourceToken>>>[registered()]),
      directory: directory,
    );

    // Act
    final Result<OnboardingPhase> result = await m.run();

    // Assert
    AuthExpect.phase(AuthExpect.ok(result), OnboardingPhase.ready);
    expect(directory.getCount, 0);
  });

  test(
    'registered but app onboarding claim absent → needsOnboarding',
    () async {
      // Arrange
      final OnboardingMachine m = machine(
        FakeAuth(<Map<ResourceKey, Result<ResourceToken>>>[registered()]),
        b: backend(appClaim: 'onboarded'),
      );

      // Act
      final Result<OnboardingPhase> result = await m.run();

      // Assert
      AuthExpect.phase(AuthExpect.ok(result), OnboardingPhase.needsOnboarding);
    },
  );

  test('unregistered → GET 200 → force-refresh → ready', () async {
    // Arrange
    final FakeUserDirectory directory = FakeUserDirectory(getStatus: 200);
    final OnboardingMachine m = machine(
      FakeAuth(<Map<ResourceKey, Result<ResourceToken>>>[
        unregistered(),
        registered(),
      ]),
      directory: directory,
    );

    // Act
    final Result<OnboardingPhase> result = await m.run();

    // Assert
    AuthExpect.phase(AuthExpect.ok(result), OnboardingPhase.ready);
    expect(directory.getCount, 1);
    expect(directory.postCount, 0);
  });

  test('unregistered → GET 404 → POST 201 → refresh → ready', () async {
    // Arrange
    final FakeUserDirectory directory = FakeUserDirectory(
      getStatus: 404,
      postStatus: 201,
    );
    final OnboardingMachine m = machine(
      FakeAuth(<Map<ResourceKey, Result<ResourceToken>>>[
        unregistered(),
        registered(),
      ]),
      directory: directory,
    );

    // Act
    final Result<OnboardingPhase> result = await m.run();

    // Assert
    AuthExpect.phase(AuthExpect.ok(result), OnboardingPhase.ready);
    expect(directory.postCount, 1);
  });

  test('POST 409 is treated as create-or-ok', () async {
    // Arrange
    final FakeUserDirectory directory = FakeUserDirectory(
      getStatus: 404,
      postStatus: 409,
    );
    final OnboardingMachine m = machine(
      FakeAuth(<Map<ResourceKey, Result<ResourceToken>>>[
        unregistered(),
        registered(),
      ]),
      directory: directory,
    );

    // Act + Assert
    AuthExpect.phase(AuthExpect.ok(await m.run()), OnboardingPhase.ready);
  });

  test('GET 500 → error', () async {
    // Arrange
    final OnboardingMachine m = machine(
      FakeAuth(<Map<ResourceKey, Result<ResourceToken>>>[unregistered()]),
      directory: FakeUserDirectory(getStatus: 500),
    );

    // Act + Assert
    expect(await m.run(), isA<Failure<OnboardingPhase>>());
    AuthExpect.phase(m.phase, OnboardingPhase.error);
  });

  test('transport failure → error', () async {
    // Arrange
    final OnboardingMachine m = machine(
      FakeAuth(<Map<ResourceKey, Result<ResourceToken>>>[unregistered()]),
      directory: FakeUserDirectory(throwOnGet: true),
    );

    // Act + Assert
    expect(await m.run(), isA<Failure<OnboardingPhase>>());
  });

  test('claim still absent after create → OnboardingClaimMissing', () async {
    // Arrange — both batches unregistered.
    final OnboardingMachine m = machine(
      FakeAuth(<Map<ResourceKey, Result<ResourceToken>>>[
        unregistered(),
        unregistered(),
      ]),
      directory: FakeUserDirectory(getStatus: 404, postStatus: 201),
    );

    // Act
    final Result<OnboardingPhase> result = await m.run();

    // Assert
    expect(AuthExpect.err(result).title, 'OnboardingClaimMissing');
  });

  test('batch acquisition failure → error', () async {
    // Arrange
    final OnboardingMachine m = machine(
      FakeAuth(<Map<ResourceKey, Result<ResourceToken>>>[
        <ResourceKey, Result<ResourceToken>>{
          key: const Failure<ResourceToken>(
            Problem(type: 't', title: 'down', status: 503),
          ),
        },
      ]),
    );

    // Act + Assert
    expect(await m.run(), isA<Failure<OnboardingPhase>>());
  });

  test('markStaleClaim errors without re-detecting', () {
    // Arrange
    final OnboardingMachine m = machine(
      FakeAuth(<Map<ResourceKey, Result<ResourceToken>>>[registered()]),
    );

    // Act
    final Result<OnboardingPhase> result = m.markStaleClaim();

    // Assert
    expect(
      AuthExpect.err(result).type,
      'urn:diene:problem:onboarding-stale-claim',
    );
    AuthExpect.phase(m.phase, OnboardingPhase.error);
  });

  test('multi-backend: A ready while B errors (no state bleed)', () async {
    // Arrange
    final ResourceKey keyB = AuthFixtures.resourceKey(service: 'billing');
    final BackendRegistry registry = BackendRegistry(<RegisteredBackend>[
      backend(),
      RegisteredBackend(
        backendId: 'secondary',
        resources: <ResourceKey>[keyB],
        onboardingResource: keyB,
      ),
    ]);
    // Shared auth: primary key registered, billing key failed.
    final FakeAuth auth = FakeAuth(<Map<ResourceKey, Result<ResourceToken>>>[
      <ResourceKey, Result<ResourceToken>>{
        key: Success<ResourceToken>(
          AuthFixtures.resourceToken(
            now: now,
            jwtToken: AuthFixtures.registeredJwt(key),
          ),
        ),
        keyB: const Failure<ResourceToken>(
          Problem(type: 't', title: 'down', status: 503),
        ),
      },
    ]);
    final MultiBackendOnboarding onboarding = MultiBackendOnboarding(
      registry: registry,
      auth: auth,
      directory: FakeUserDirectory(),
      idToken: () async => 'id-token',
    );

    // Act
    final Map<String, Result<OnboardingPhase>> results = await onboarding
        .runAll();

    // Assert
    expect(results['primary'], isA<Success<OnboardingPhase>>());
    expect(results['secondary'], isA<Failure<OnboardingPhase>>());
    expect(onboarding.machineFor('primary').phase, OnboardingPhase.ready);
    expect(onboarding.machineFor('secondary').phase, OnboardingPhase.error);
  });
}
