import 'dart:convert';

import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:diene_auth_engine/test_helper.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import 'package:flutter_test/flutter_test.dart';

// The residual failure/edge arms the behavioural suites never reached: error
// branches, equality/hashCode contracts, guard clauses, and the const-constructor
// arms that only a non-const invocation records. Grouped by subject rather than
// by file so each block reads as a contract, not as a coverage errand.
void main() {
  final DateTime now = DateTime.utc(2026, 7, 21, 9);
  final ResourceKey key = AuthFixtures.resourceKey();

  group('SessionTokens / ResourceToken value semantics', () {
    test('equality and hashCode cover every component', () {
      // Arrange — a baseline plus one single-field mutation per component, so a
      // dropped comparison in either operator== or hashCode shows up.
      final SessionTokens base = AuthFixtures.sessionTokens(now: now);
      final List<SessionTokens> mutations = <SessionTokens>[
        AuthFixtures.sessionTokens(now: now, accessToken: 'other'),
        AuthFixtures.sessionTokens(now: now, refreshToken: 'other'),
        AuthFixtures.sessionTokens(now: now, refreshFamily: 'other'),
        AuthFixtures.sessionTokens(
          now: now,
          access: TokenLifetimes.access + const Duration(seconds: 1),
        ),
        AuthFixtures.sessionTokens(
          now: now,
          refresh: TokenLifetimes.refresh + const Duration(seconds: 1),
        ),
      ];

      // Act + Assert — identical inputs are equal AND hash alike.
      final SessionTokens twin = AuthFixtures.sessionTokens(now: now);
      expect(base, twin);
      expect(base.hashCode, twin.hashCode);
      for (final SessionTokens mutated in mutations) {
        expect(base, isNot(mutated));
        expect(base.hashCode, isNot(mutated.hashCode));
      }
      // A foreign type is never equal.
      expect(base, isNot(<String, Object?>{}));
    });

    test('ResourceToken equality and hashCode cover token + expiry', () {
      // Arrange
      final ResourceToken base = AuthFixtures.resourceToken(
        now: now,
        jwtToken: 'j',
      );

      // Act + Assert
      final ResourceToken twin = AuthFixtures.resourceToken(
        now: now,
        jwtToken: 'j',
      );
      expect(base, twin);
      expect(base.hashCode, twin.hashCode);
      expect(
        base,
        isNot(AuthFixtures.resourceToken(now: now, jwtToken: 'other')),
      );
      expect(
        base,
        isNot(
          AuthFixtures.resourceToken(
            now: now,
            jwtToken: 'j',
            ttl: TokenLifetimes.access + const Duration(seconds: 1),
          ),
        ),
      );
      expect(base, isNot(<String, Object?>{}));
    });

    test('ResourceTokenEntry pairs a key with its terminal token', () {
      // Arrange + Act — the batch entry shape (C0 §8).
      final ResourceToken token = AuthFixtures.resourceToken(
        now: now,
        jwtToken: 'j',
      );
      final ResourceTokenEntry entry = ResourceTokenEntry(
        key: key,
        token: token,
      );

      // Assert
      expect(entry.key, key);
      expect(entry.token, token);
    });

    test('ResourceKey toString names the map key', () {
      // Act + Assert — the debug rendering used in failure messages.
      expect(key.toString(), 'ResourceKey(lithium/lapras/api/root)');
    });
  });

  group('AuthCoordinator failure + invalidateAll', () {
    test('wraps a provider throw in a recoverable 401 problem', () async {
      // Arrange — the provider has no token scripted for this key, so its
      // resourceToken throws.
      final FakeAuthProvider provider = FakeAuthProvider();
      final AuthCoordinator auth = AuthCoordinator(
        provider: provider,
        now: () => now,
      );

      // Act
      final Result<ResourceToken> result = await auth.tokenFor(key);

      // Assert — a transport/provider failure becomes a Problem, never a throw
      // escaping into the caller's hot path.
      final Problem problem = AuthExpect.errType(
        result,
        'urn:diene:problem:resource-token',
      );
      expect(problem.status, 401);
      expect(problem.recoverable, isTrue);
      expect(problem.data['resource'], key.mapKey);
      expect(problem.detail, contains(key.mapKey));
    });

    test('invalidateAll drops every cached token', () async {
      // Arrange — a counting provider, since the shared fake exposes no
      // resource-token call counter.
      final _CountingProvider provider = _CountingProvider(
        AuthFixtures.resourceToken(now: now, jwtToken: 'j'),
      );
      final AuthCoordinator auth = AuthCoordinator(
        provider: provider,
        now: () => now,
      );
      await auth.tokenFor(key);
      await auth.tokenFor(key);

      // Act — the cache served the second call; invalidateAll must drop it.
      expect(provider.calls, 1);
      auth.invalidateAll();
      await auth.tokenFor(key);

      // Assert — the third call had to re-acquire.
      expect(provider.calls, 2);
    });

    test('defaults its clock to DateTime.now when none is injected', () async {
      // Arrange — the default-clock arm of the constructor.
      final AuthCoordinator auth = AuthCoordinator(
        provider: FakeAuthProvider(
          resourceTokens: <String, ResourceToken>{
            key.mapKey: AuthFixtures.resourceToken(
              now: DateTime.now(),
              jwtToken: 'j',
            ),
          },
        ),
      );

      // Act + Assert
      expect(AuthExpect.ok(await auth.tokenFor(key)).token, 'j');
    });
  });

  group('Claims.decode non-standard map payloads', () {
    test('normalizes a JSON object whose values are heterogeneous', () {
      // Arrange — the Map-but-not-Map<String,Object?> normalization arm.
      final String token = AuthFixtures.jwt(<String, Object?>{
        'home_landscape': 'pichu',
        'nested': <String, Object?>{'deep': 1},
        'list': <Object?>[1, 'two', null],
        'nil': null,
      });

      // Act
      final Map<String, Object?> claims = Claims.decode(token);

      // Assert
      expect(claims['home_landscape'], 'pichu');
      expect(claims['list'], <Object?>[1, 'two', null]);
      expect(claims.containsKey('nil'), isTrue);
      expect(Claims.home(claims), 'pichu');
    });

    test('treats a non-object JWT payload as absent claims', () {
      // Arrange — a token whose payload segment decodes to a JSON ARRAY, which
      // is valid JSON but carries no claims.
      final String arrayPayload = base64Url
          .encode(utf8.encode('[1,2,3]'))
          .replaceAll('=', '');

      // Act + Assert — every "not a claims object" shape reads as empty rather
      // than throwing into the caller.
      expect(Claims.decode('only-one-segment'), isEmpty);
      expect(Claims.decode('a.!!!not-base64!!!.c'), isEmpty);
      expect(Claims.decode('header.$arrayPayload.sig'), isEmpty);
    });
  });

  group('SessionController failure arms', () {
    test(
      'surfaces a refresh transport failure as a recoverable problem',
      () async {
        // Arrange — a session whose provider throws on refresh.
        final FakeAuthProvider provider = FakeAuthProvider(
          onSignIn: () => AuthFixtures.sessionTokens(now: now),
        );
        final SessionController session = SessionController(
          provider: provider,
          now: () => now,
        );
        await session.signIn();

        // Act — no onRefresh scripted, so the provider throws.
        final Result<SessionTokens> result = await session.refresh();

        // Assert — recoverable, so the UI may retry rather than sign out.
        final Problem problem = AuthExpect.errType(
          result,
          'urn:diene:problem:refresh',
        );
        expect(problem.status, 401);
        expect(problem.recoverable, isTrue);
        expect(session.status, SessionStatus.authenticated);
      },
    );

    test(
      'surfaces a re-mint transport failure as a recoverable problem',
      () async {
        // Arrange
        final FakeAuthProvider provider = FakeAuthProvider(
          onSignIn: () => AuthFixtures.sessionTokens(now: now),
        );
        final SessionController session = SessionController(
          provider: provider,
          now: () => now,
        );
        await session.signIn();

        // Act — no onReMint scripted.
        final Result<SessionTokens> result = await session.onAppOpen();

        // Assert
        final Problem problem = AuthExpect.errType(
          result,
          'urn:diene:problem:remint',
        );
        expect(problem.status, 401);
        expect(problem.recoverable, isTrue);
      },
    );

    test('signs out and reports expiry when the refresh window has closed on '
        'app open', () async {
      // Arrange — sign in, then open the app after the refresh lifetime.
      final FakeAuthProvider provider = FakeAuthProvider(
        onSignIn: () => AuthFixtures.sessionTokens(now: now),
      );
      DateTime clock = now;
      final SessionController session = SessionController(
        provider: provider,
        now: () => clock,
      );
      await session.signIn();
      clock = now.add(TokenLifetimes.refresh + const Duration(minutes: 1));

      // Act
      final Result<SessionTokens> result = await session.onAppOpen();

      // Assert — an expired refresh window is a hard sign-out, not a retry.
      AuthExpect.status(
        AuthExpect.errType(result, 'urn:diene:problem:refresh-expired'),
        401,
      );
      expect(session.status, SessionStatus.unauthenticated);
      expect(session.tokens, isNull);
      expect(provider.signOutCount, 1);
    });

    test('exposes the failure problem after a failed sign-in', () async {
      // Arrange
      final FakeAuthProvider provider = FakeAuthProvider(
        throwOnSignIn: StateError('idp down'),
      );
      final SessionController session = SessionController(
        provider: provider,
        now: () => now,
      );

      // Act
      final Result<SessionTokens> result = await session.signIn();

      // Assert — the problem is readable off the controller for UI gating.
      AuthExpect.errType(result, 'urn:diene:problem:auth');
      expect(session.status, SessionStatus.failed);
      expect(session.problem?.type, 'urn:diene:problem:auth');
      expect(session.problem?.recoverable, isTrue);
    });

    test('defaults its clock to DateTime.now when none is injected', () async {
      // Arrange — the default-clock arm; lifetimes are validated against it.
      final SessionController session = SessionController(
        provider: FakeAuthProvider(
          onSignIn: () => AuthFixtures.sessionTokens(now: DateTime.now()),
        ),
      );

      // Act + Assert
      expect(AuthExpect.ok(await session.signIn()).refreshFamily, 'family');
    });

    test('rejects a provider-issued REFRESH token that outlives the family '
        'lifetime', () async {
      // Arrange — the access half is legal but the refresh half overshoots.
      // Lifetimes are ENFORCED, not trusted (C0 §12), so an over-long refresh
      // token must be refused even though the provider offered it.
      final FakeAuthProvider provider = FakeAuthProvider(
        onSignIn: () => AuthFixtures.sessionTokens(
          now: now,
          refresh: TokenLifetimes.refresh + const Duration(days: 1),
        ),
      );
      final SessionController session = SessionController(
        provider: provider,
        now: () => now,
      );

      // Act
      final Result<SessionTokens> result = await session.signIn();

      // Assert — the over-long grant is rejected, not silently accepted.
      final Problem problem = AuthExpect.errType(
        result,
        'urn:diene:problem:auth',
      );
      expect(problem.detail, contains('Refresh token lifetime'));
      expect(session.status, SessionStatus.failed);
      expect(session.tokens, isNull);
    });
  });

  group('AuthEngineConfig validation arms', () {
    Map<String, Object?> block({
      Object? issuer = 'https://api.lithium.mew.cluster.atomi.cloud',
      Object? endpoint = 'https://logto.example.com',
      Object? appId = 'mobile',
      Object? redirectUri = 'cloud.atomi.app://callback',
      Object? extra,
      String extraKey = 'appHandoffMount',
    }) => <String, Object?>{
      'issuer': ?issuer,
      'endpoint': ?endpoint,
      'appId': ?appId,
      'redirectUri': ?redirectUri,
      extraKey: ?extra,
    };

    test('rejects a non-string or blank URI value', () {
      // Act + Assert — a coerced 7 or '' must be refused, not stringified.
      expect(
        () => AuthEngineConfig.fromBlock(block(endpoint: 7)),
        throwsFormatException,
      );
      expect(
        () => AuthEngineConfig.fromBlock(block(endpoint: '')),
        throwsFormatException,
      );
    });

    test('rejects a relative URI where an absolute one is required', () {
      // Act + Assert — the baked issuer/endpoint must be absolute.
      expect(
        () => AuthEngineConfig.fromBlock(block(endpoint: '/relative')),
        throwsFormatException,
      );
    });

    test('rejects a non-string or blank appId', () {
      // Act + Assert
      expect(
        () => AuthEngineConfig.fromBlock(block(appId: 7)),
        throwsFormatException,
      );
      expect(
        () => AuthEngineConfig.fromBlock(block(appId: '')),
        throwsFormatException,
      );
    });

    test('rejects an appHandoffMount that does not begin with a slash', () {
      // Act + Assert — the mount is joined verbatim onto the base.
      expect(
        () => AuthEngineConfig.fromBlock(block(extra: 'app-handoff')),
        throwsFormatException,
      );
    });

    test('falls back to the defaults for a wrong-typed optional block', () {
      // Arrange — scopes/allowlist/mount all supplied at the WRONG type, plus an
      // empty allowlist, which must not disable the gate.
      final AuthEngineConfig config =
          AuthEngineConfig.fromBlock(<String, Object?>{
            ...block(extra: null),
            'scopes': 'openid',
            'endpointSuffixAllowlist': <String>[],
            'appHandoffMount': 7,
            'postLogoutRedirectUri': '',
          });

      // Assert — the baked defaults hold; an empty allowlist never means "any".
      expect(config.scopes, <String>['openid', 'offline_access']);
      expect(config.endpointSuffixAllowlist, <String>['cluster.atomi.cloud']);
      expect(config.appHandoffMount, AppHandoffConstants.defaultMount);
      expect(config.redeemPath, '/app-handoff/redeem');
      expect(config.postLogoutRedirectUri, isNull);
      expect(
        config.allowsUrl(Uri.parse('https://evil.example.com/x')),
        isFalse,
      );
    });

    test('accepts a supplied postLogoutRedirectUri and custom lists', () {
      // Arrange
      final AuthEngineConfig config = AuthEngineConfig.fromBlock(
        <String, Object?>{
          ...block(extra: null),
          'postLogoutRedirectUri': 'cloud.atomi.app://signed-out',
          'scopes': <Object?>['openid', 'profile'],
          'endpointSuffixAllowlist': <Object?>['example.test'],
        },
      );

      // Assert
      expect(
        config.postLogoutRedirectUri,
        Uri.parse('cloud.atomi.app://signed-out'),
      );
      expect(config.scopes, <String>['openid', 'profile']);
      expect(config.allowsUrl(Uri.parse('https://a.example.test/x')), isTrue);
      expect(config.allowsUrl(Uri.parse('https://example.test/x')), isTrue);
    });

    test('the default const constructor bakes the family defaults', () {
      // Arrange + Act — the direct (non-factory) construction arm.
      final AuthEngineConfig config = AuthEngineConfig(
        issuer: Uri.parse('https://api.lithium.mew.cluster.atomi.cloud'),
        endpoint: Uri.parse('https://logto.example.com'),
        appId: 'mobile',
        redirectUri: Uri.parse('cloud.atomi.app://callback'),
        scopes: const <String>['openid'],
      );

      // Assert
      expect(config.appHandoffMount, AppHandoffConstants.defaultMount);
      expect(config.endpointSuffixAllowlist, <String>['cluster.atomi.cloud']);
      expect(config.postLogoutRedirectUri, isNull);
    });
  });

  group('RegisteredBackend argument validation', () {
    test('rejects a blank backend id', () {
      // Act + Assert
      expect(
        () => RegisteredBackend(
          backendId: '',
          resources: <ResourceKey>[key],
          onboardingResource: key,
        ),
        throwsArgumentError,
      );
    });

    test('rejects an empty resource list', () {
      // Act + Assert — a backend with no resources has nothing to onboard to.
      expect(
        () => RegisteredBackend(
          backendId: 'api',
          resources: const <ResourceKey>[],
          onboardingResource: key,
        ),
        throwsArgumentError,
      );
    });
  });

  group('ReturnTo rejection arms', () {
    test('rejects a normalized path that collapses to a protocol-relative '
        'form', () {
      // Arrange — `/.//evil.com` normalizes to path `//evil.com` with NO
      // authority, so the scheme/authority guard alone would let it through;
      // the single-slash guard is what actually stops the open redirect.
      final Result<Uri> resolved = ReturnTo.resolve('/.//evil.com/x');
      final Result<String> captured = ReturnTo.capture(
        Uri.parse('/x').replace(path: '//evil.com/x'),
      );

      // Act + Assert
      AuthExpect.status(
        AuthExpect.errType(resolved, 'urn:diene:problem:return-to'),
        400,
      );
      AuthExpect.errType(captured, 'urn:diene:problem:return-to');
    });

    test('rejects an empty returnTo', () {
      // Act + Assert
      AuthExpect.errType(ReturnTo.resolve(''), 'urn:diene:problem:return-to');
    });

    test('rejects a returnTo that is not a valid URI reference', () {
      // Arrange — an unterminated IPv6 bracket makes Uri.parse throw.
      final Result<Uri> result = ReturnTo.resolve('//[');

      // Act + Assert — a parse failure is a rejection, never a followed target.
      final Problem problem = AuthExpect.errType(
        result,
        'urn:diene:problem:return-to',
      );
      expect(problem.detail, contains('not a valid URI reference'));
    });

    test('rejects a scheme-carrying returnTo on the way out', () {
      // Act + Assert — the outbound re-validation, not just the inbound one.
      final Problem problem = AuthExpect.errType(
        ReturnTo.resolve('https://evil.example.com/x'),
        'urn:diene:problem:return-to',
      );
      expect(problem.detail, contains('scheme/authority'));
    });
  });

  group('HomeClaimResolver failure + no-store arms', () {
    LandscapeSelectorClient selectorReturning(String landscape) =>
        LandscapeSelectorClient(
          source: FakeLandscapeSelectorSource(
            doc: LandscapeSelectorDoc(
              platform: 'lithium',
              tier: 'lapras',
              landscapes: <LandscapeEntry>[
                LandscapeEntry(name: landscape, region: 'ap-southeast-1'),
              ],
            ),
          ),
          pinger: FakeRegionPinger(<String, Duration?>{
            landscape: const Duration(milliseconds: 5),
          }),
        );

    test('maps a claim-reader throw to a recoverable 503 problem', () async {
      // Arrange — the stored-token read itself fails.
      final HomeClaimResolver resolver = HomeClaimResolver(
        claimReader: () async => throw StateError('token store unreadable'),
        selector: selectorReturning('pichu'),
      );

      // Act
      final Result<String?> read = await resolver.authoritativeHome();

      // Assert
      final Problem problem = AuthExpect.errType(
        read,
        'urn:diene:problem:home-claim-read',
      );
      expect(problem.status, 503);
      expect(problem.recoverable, isTrue);
      // resolve() propagates the same problem rather than falling to Doc B.
      AuthExpect.errType(
        await resolver.resolve(),
        'urn:diene:problem:home-claim-read',
      );
    });

    test(
      'maps a forced-reader throw to the same recoverable problem',
      () async {
        // Arrange — the post-OnboardSync confirmation read fails.
        final HomeClaimResolver resolver = HomeClaimResolver(
          claimReader: () async => null,
          selector: selectorReturning('pichu'),
          forcedClaimReader: () async => throw StateError('refresh failed'),
        );

        // Act + Assert
        AuthExpect.status(
          AuthExpect.errType(
            await resolver.confirmedHome(),
            'urn:diene:problem:home-claim-read',
          ),
          503,
        );
      },
    );

    test('confirmedHome fails closed on a blank forced claim', () async {
      // Arrange — a blank claim must read as "not confirmed", never as a value.
      final HomeClaimResolver resolver = HomeClaimResolver(
        claimReader: () async => null,
        selector: selectorReturning('pichu'),
        forcedClaimReader: () async => '',
      );

      // Act + Assert
      expect(AuthExpect.ok(await resolver.confirmedHome()), isNull);
    });

    test('tolerates an absent store on mirror, commit, and forget', () async {
      // Arrange — the store is OPTIONAL; every write path must no-op safely.
      final HomeClaimResolver resolver = HomeClaimResolver(
        claimReader: () async => 'pichu',
        selector: selectorReturning('raichu'),
      );

      // Act
      final Result<HomeResolution> resolved = await resolver.resolve();
      await resolver.commit('pichu');
      await resolver.forget();

      // Assert — the authoritative claim still decides, with no store present.
      final HomeResolution home = AuthExpect.ok(resolved);
      expect(home.landscape, 'pichu');
      expect(home.kind, HomeResolutionKind.fromClaim);
    });

    test(
      'swallows a store write failure — the cache never overrides the JWT',
      () async {
        // Arrange — a mirror store whose write throws.
        final HomeClaimResolver resolver = HomeClaimResolver(
          claimReader: () async => 'pichu',
          selector: selectorReturning('raichu'),
          store: _ThrowingHomeClaimStore(),
        );

        // Act
        final Result<HomeResolution> resolved = await resolver.resolve();

        // Assert — best-effort mirror; the claim decision survives.
        expect(AuthExpect.ok(resolved).landscape, 'pichu');
        await resolver.commit('pichu');
      },
    );

    test(
      'jwtHomeClaimReader yields null for a missing or blank token',
      () async {
        // Arrange
        final HomeClaimReader absent = jwtHomeClaimReader(() async => null);
        final HomeClaimReader blank = jwtHomeClaimReader(() async => '');
        final HomeClaimReader present = jwtHomeClaimReader(
          () async => AuthFixtures.jwt(<String, Object?>{
            Claims.homeLandscape: 'pichu',
          }),
        );

        // Act + Assert — no token means the Doc B sign-up path, not a failure.
        expect(await absent(), isNull);
        expect(await blank(), isNull);
        expect(await present(), 'pichu');
      },
    );

    test('HomeResolution carries the landscape and its resolution kind', () {
      // Arrange + Act — the direct construction arm.
      const HomeResolution resolution = HomeResolution(
        landscape: 'pichu',
        kind: HomeResolutionKind.selected,
      );

      // Assert
      expect(resolution.landscape, 'pichu');
      expect(resolution.kind, HomeResolutionKind.selected);
    });
  });

  group('MultiBackendOnboarding / OnboardingMachine residual arms', () {
    RegisteredBackend backend(String id, {String service = 'api'}) {
      final ResourceKey resource = AuthFixtures.resourceKey(service: service);
      return RegisteredBackend(
        backendId: id,
        resources: <ResourceKey>[resource],
        onboardingResource: resource,
      );
    }

    test('machineFor rejects an unregistered backend id', () {
      // Arrange
      final MultiBackendOnboarding onboarding = MultiBackendOnboarding(
        registry: BackendRegistry(<RegisteredBackend>[backend('api')]),
        auth: FakeAuth(<Map<ResourceKey, Result<ResourceToken>>>[
          <ResourceKey, Result<ResourceToken>>{},
        ]),
        directory: FakeUserDirectory(),
        idToken: () async => null,
      );

      // Act + Assert — a typo must fail loudly, not silently no-op.
      expect(() => onboarding.machineFor('nope'), throwsArgumentError);
      expect(onboarding.machineFor('api').backendId, 'api');
      expect(onboarding.phases, <String, OnboardingPhase>{
        'api': OnboardingPhase.bootstrapping,
      });
    });

    test('a machine exposes its backend id and required resources', () {
      // Arrange
      final RegisteredBackend registered = backend(
        'billing',
        service: 'billing',
      );
      final OnboardingMachine machine = OnboardingMachine(
        backend: registered,
        auth: FakeAuth(<Map<ResourceKey, Result<ResourceToken>>>[
          <ResourceKey, Result<ResourceToken>>{},
        ]),
        directory: FakeUserDirectory(),
        idToken: () async => null,
      );

      // Act + Assert
      expect(machine.backendId, 'billing');
      expect(machine.resources, registered.resources);
    });

    test(
      'errors when POST /User returns a non-created, non-conflict status',
      () async {
        // Arrange — GET says 404 (create path) and the create itself is refused.
        final RegisteredBackend registered = backend('api');
        final ResourceKey resource = registered.onboardingResource;
        final OnboardingMachine machine = OnboardingMachine(
          backend: registered,
          auth: FakeAuth(<Map<ResourceKey, Result<ResourceToken>>>[
            <ResourceKey, Result<ResourceToken>>{
              resource: Ok<ResourceToken>(
                AuthFixtures.resourceToken(
                  now: now,
                  jwtToken: AuthFixtures.unregisteredJwt(resource),
                ),
              ),
            },
          ]),
          directory: FakeUserDirectory(getStatus: 404, postStatus: 500),
          idToken: () async => 'header.id.sig',
        );

        // Act
        final Result<OnboardingPhase> result = await machine.run();

        // Assert
        final Problem problem = AuthExpect.err(result);
        expect(problem.detail, contains('POST /User'));
        expect(machine.phase, OnboardingPhase.error);
      },
    );

    test('errors when the post-create force-refresh batch fails', () async {
      // Arrange — the create succeeds, then the re-acquisition returns an Err.
      final RegisteredBackend registered = backend('api');
      final ResourceKey resource = registered.onboardingResource;
      final OnboardingMachine machine = OnboardingMachine(
        backend: registered,
        auth: FakeAuth(<Map<ResourceKey, Result<ResourceToken>>>[
          <ResourceKey, Result<ResourceToken>>{
            resource: Ok<ResourceToken>(
              AuthFixtures.resourceToken(
                now: now,
                jwtToken: AuthFixtures.unregisteredJwt(resource),
              ),
            ),
          },
          <ResourceKey, Result<ResourceToken>>{
            resource: const Err<ResourceToken>(
              Problem(
                type: 'urn:diene:problem:resource-token',
                title: 'token gone',
                status: 401,
              ),
            ),
          },
        ]),
        directory: FakeUserDirectory(getStatus: 404, postStatus: 201),
        idToken: () async => 'header.id.sig',
      );

      // Act
      final Result<OnboardingPhase> result = await machine.run();

      // Assert — the refresh failure surfaces, not the claim-missing problem.
      AuthExpect.errType(result, 'urn:diene:problem:resource-token');
      expect(machine.phase, OnboardingPhase.error);
    });

    test(
      'errors with a 401 when the ID token needed to create is absent',
      () async {
        // Arrange — GET 404 means create, but there is no ID token to send.
        final RegisteredBackend registered = backend('api');
        final ResourceKey resource = registered.onboardingResource;
        final OnboardingMachine machine = OnboardingMachine(
          backend: registered,
          auth: FakeAuth(<Map<ResourceKey, Result<ResourceToken>>>[
            <ResourceKey, Result<ResourceToken>>{
              resource: Ok<ResourceToken>(
                AuthFixtures.resourceToken(
                  now: now,
                  jwtToken: AuthFixtures.unregisteredJwt(resource),
                ),
              ),
            },
          ]),
          directory: FakeUserDirectory(getStatus: 404),
          idToken: () async => null,
        );

        // Act
        final Result<OnboardingPhase> result = await machine.run();

        // Assert
        AuthExpect.status(
          AuthExpect.errType(result, 'urn:diene:problem:onboarding-idtoken'),
          401,
        );
      },
    );
  });

  group('SignInCoordinator propagation arms', () {
    test('propagates a pre-login home-claim read failure', () async {
      // Arrange — the very first step fails, so login must not even be tried.
      final FakeAuthProvider provider = FakeAuthProvider(
        onSignIn: () => AuthFixtures.sessionTokens(now: now),
      );
      final SignInCoordinator coordinator = SignInCoordinator(
        session: SessionController(provider: provider, now: () => now),
        homeResolver: HomeClaimResolver(
          claimReader: () async => throw StateError('unreadable'),
          selector: LandscapeSelectorClient(
            source: FakeLandscapeSelectorSource(
              error: const FormatException('no doc'),
            ),
            pinger: FakeRegionPinger(const <String, Duration?>{}),
          ),
        ),
        onboarding: MultiBackendOnboarding(
          registry: BackendRegistry(<RegisteredBackend>[
            RegisteredBackend(
              backendId: 'api',
              resources: <ResourceKey>[key],
              onboardingResource: key,
            ),
          ]),
          auth: FakeAuth(<Map<ResourceKey, Result<ResourceToken>>>[
            <ResourceKey, Result<ResourceToken>>{},
          ]),
          directory: FakeUserDirectory(),
          idToken: () async => null,
        ),
      );

      // Act
      final Result<SignInResult> result = await coordinator.signIn();

      // Assert — the read problem propagates and no sign-in was attempted.
      AuthExpect.errType(result, 'urn:diene:problem:home-claim-read');
      expect(provider.signInCount, 0);
    });

    test('propagates a POST-login authoritative re-read failure', () async {
      // Arrange — the pre-login read succeeds (routing straight home, so Doc B
      // never runs) but the re-read of the FRESHLY ISSUED token fails. That
      // re-read exists so a server-changed/removed home_landscape overrides the
      // pre-login value, and a failure there must surface rather than silently
      // keep the stale home.
      int reads = 0;
      final FakeAuthProvider provider = FakeAuthProvider(
        onSignIn: () => AuthFixtures.sessionTokens(now: now),
      );
      final SignInCoordinator coordinator = SignInCoordinator(
        session: SessionController(provider: provider, now: () => now),
        homeResolver: HomeClaimResolver(
          claimReader: () async {
            reads += 1;
            if (reads > 1) {
              throw StateError('issued-token read failed');
            }
            return 'pichu';
          },
          selector: LandscapeSelectorClient(
            source: FakeLandscapeSelectorSource(
              error: const FormatException('Doc B must not run here'),
            ),
            pinger: FakeRegionPinger(const <String, Duration?>{}),
          ),
        ),
        onboarding: MultiBackendOnboarding(
          registry: BackendRegistry(<RegisteredBackend>[
            RegisteredBackend(
              backendId: 'api',
              resources: <ResourceKey>[key],
              onboardingResource: key,
            ),
          ]),
          auth: FakeAuth(<Map<ResourceKey, Result<ResourceToken>>>[
            <ResourceKey, Result<ResourceToken>>{},
          ]),
          directory: FakeUserDirectory(),
          idToken: () async => 'header.id.sig',
        ),
      );

      // Act
      final Result<SignInResult> result = await coordinator.signIn();

      // Assert — login DID happen, then the re-read failure propagated.
      AuthExpect.errType(result, 'urn:diene:problem:home-claim-read');
      expect(provider.signInCount, 1);
      expect(reads, 2);
    });

    test('propagates a confirmation failure on the sign-up path', () async {
      // Arrange — no stored claim, so Doc B selects a landscape (sign-up).
      // Onboarding then succeeds, and the FORCE-FRESH confirmation read fails.
      // The locally selected landscape must NEVER be mirrored as if it were a
      // confirmed claim (C0 §13), so the failure has to surface.
      final FakeAuthProvider provider = FakeAuthProvider(
        onSignIn: () => AuthFixtures.sessionTokens(now: now),
      );
      final MemoryHomeClaimStore store = MemoryHomeClaimStore();
      final SignInCoordinator coordinator = SignInCoordinator(
        session: SessionController(provider: provider, now: () => now),
        homeResolver: HomeClaimResolver(
          claimReader: () async => null,
          selector: LandscapeSelectorClient(
            source: FakeLandscapeSelectorSource(
              doc: const LandscapeSelectorDoc(
                platform: 'lithium',
                tier: 'lapras',
                landscapes: <LandscapeEntry>[
                  LandscapeEntry(name: 'pichu', region: 'ap-southeast-1'),
                ],
              ),
            ),
            pinger: FakeRegionPinger(<String, Duration?>{
              'pichu': const Duration(milliseconds: 5),
            }),
          ),
          store: store,
          forcedClaimReader: () async =>
              throw StateError('forced claim read failed'),
        ),
        onboarding: MultiBackendOnboarding(
          registry: BackendRegistry(<RegisteredBackend>[
            RegisteredBackend(
              backendId: 'api',
              resources: <ResourceKey>[key],
              onboardingResource: key,
            ),
          ]),
          auth: FakeAuth(<Map<ResourceKey, Result<ResourceToken>>>[
            <ResourceKey, Result<ResourceToken>>{
              key: Ok<ResourceToken>(
                AuthFixtures.resourceToken(
                  now: now,
                  jwtToken: AuthFixtures.registeredJwt(key),
                ),
              ),
            },
          ]),
          directory: FakeUserDirectory(),
          idToken: () async => 'header.id.sig',
        ),
      );

      // Act
      final Result<SignInResult> result = await coordinator.signIn();

      // Assert — the confirmation failure surfaces and NOTHING was mirrored.
      AuthExpect.errType(result, 'urn:diene:problem:home-claim-read');
      expect(store.value, isNull);
      expect(store.writes, 0);
    });

    test(
      'SignInResult carries home, phases, and the returnTo continuation',
      () {
        // Arrange + Act — the direct construction arm.
        final SignInResult result = SignInResult(
          home: const HomeResolution(
            landscape: 'pichu',
            kind: HomeResolutionKind.fromClaim,
          ),
          phases: <String, Result<OnboardingPhase>>{
            'api': const Ok<OnboardingPhase>(OnboardingPhase.ready),
          },
          continueTo: Uri.parse('/protected?x=1'),
        );

        // Assert
        expect(result.home.landscape, 'pichu');
        expect(result.phases['api'], isA<Ok<OnboardingPhase>>());
        expect(result.continueTo, Uri.parse('/protected?x=1'));
      },
    );
  });

  group('deferred-login value shapes', () {
    test('DeviceInfo carries every optional field when supplied', () {
      // Arrange + Act — the all-fields-present arm of toJson.
      const DeviceInfo device = DeviceInfo(
        platform: 'android',
        appVersion: '2.0.0',
        osVersion: '15',
        model: 'Pixel 9',
      );

      // Assert
      expect(device.toJson(), <String, Object?>{
        'platform': 'android',
        'appVersion': '2.0.0',
        'osVersion': '15',
        'model': 'Pixel 9',
      });
    });

    test('DeviceInfo is constructible at runtime, not only as a const', () {
      // Arrange — a const invocation is folded at compile time, so the platform
      // field is exercised here through a NON-const construction built from a
      // runtime value.
      final String platform = <String>['android', 'ios'].first;
      final DeviceInfo device = DeviceInfo(platform: platform);

      // Assert — the optional telemetry fields stay absent.
      expect(device.platform, 'android');
      expect(device.toJson(), <String, Object?>{'platform': 'android'});
    });

    test('ClipboardCarrierReader is constructible at runtime', () {
      // Arrange + Act — a const invocation is compile-time folded, so the
      // constructor is exercised through a NON-const construction.
      // ignore: prefer_const_constructors
      final ClipboardCarrierReader reader = ClipboardCarrierReader();

      // Assert
      expect(reader, isA<ClipboardCarrierSource>());
    });
  });
}

/// Provider that counts resource-token acquisitions, so a cache-vs-reacquire
/// assertion is exact. The shared [FakeAuthProvider] exposes no such counter.
final class _CountingProvider implements AuthProvider {
  _CountingProvider(this._token);

  final ResourceToken _token;
  int calls = 0;

  @override
  Future<ResourceToken> resourceToken(ResourceKey key) async {
    calls += 1;
    return _token;
  }

  @override
  Future<SessionTokens> signIn({
    Map<String, String> extraParams = const <String, String>{},
  }) => throw UnimplementedError();
  @override
  Future<SessionTokens> refresh(SessionTokens current) =>
      throw UnimplementedError();
  @override
  Future<SessionTokens> reMintOnOpen(SessionTokens current) =>
      throw UnimplementedError();
  @override
  Future<void> signOut() async {}
  @override
  Future<String?> idToken() async => null;
  @override
  Future<String?> freshClaimToken() async => null;
}

/// Home claim store whose write always fails — the mirror is non-authoritative,
/// so a failed write must never change the resolved home.
final class _ThrowingHomeClaimStore implements HomeClaimStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String landscape) async =>
      throw StateError('mirror store unavailable');

  @override
  Future<void> clear() async {}
}
