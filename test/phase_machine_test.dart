import 'package:diene_flutter_base/core/result.dart';
import 'package:diene_flutter_base/onboarding/phase_machine.dart';
import 'package:flutter_test/flutter_test.dart';

const ResourceKey _primaryApi = ResourceKey(
  platform: 'platform',
  landscape: 'lapras',
  service: 'service',
  resourceName: 'api',
);
const ResourceKey _primaryFiles = ResourceKey(
  platform: 'platform',
  landscape: 'lapras',
  service: 'service',
  resourceName: 'files',
);
const ResourceKey _secondaryApi = ResourceKey(
  platform: 'platform',
  landscape: 'lapras',
  service: 'billing-service',
  resourceName: 'api',
);

final class _Tokens implements TokenProvider {
  _Tokens({
    required this.claimsBefore,
    Map<ResourceKey, Map<String, Object?>>? claimsAfter,
    this.idTokenValue = 'raw-id-token',
    this.failing = const <ResourceKey>{},
    this.omit = const <ResourceKey>{},
  }) : claimsAfter = claimsAfter ?? claimsBefore;

  final Map<ResourceKey, Map<String, Object?>> claimsBefore;
  final Map<ResourceKey, Map<String, Object?>> claimsAfter;
  final String? idTokenValue;
  final Set<ResourceKey> failing;

  /// Keys deliberately dropped from the batch, to prove totality is checked.
  final Set<ResourceKey> omit;

  int batches = 0;
  int refreshes = 0;

  @override
  Future<Map<ResourceKey, Result<ResourceToken>>> acquireAll(
    Set<ResourceKey> keys, {
    bool forceRefresh = false,
  }) async {
    batches += 1;
    if (forceRefresh) {
      refreshes += 1;
    }
    final Map<ResourceKey, Map<String, Object?>> source = forceRefresh
        ? claimsAfter
        : claimsBefore;
    return <ResourceKey, Result<ResourceToken>>{
      for (final ResourceKey key in keys)
        if (!omit.contains(key))
          key: failing.contains(key)
              ? const Failure<ResourceToken>(
                  Problem(
                    type: 'urn:diene:problem:token',
                    title: 'Token acquisition failed',
                    status: 503,
                  ),
                )
              : Success<ResourceToken>(
                  ResourceToken(
                    raw: 'token-${key.mapKey}${forceRefresh ? '-fresh' : ''}',
                    claims: source[key] ?? const <String, Object?>{},
                    expiresAt: DateTime.utc(2026, 7, 27, 10),
                  ),
                ),
    };
  }

  @override
  Future<String?> idToken() async => idTokenValue;
}

final class _Client implements OnboardSyncClient {
  _Client({this.getStatus = 404, this.postStatus = 201});

  int getStatus;
  int postStatus;
  int gets = 0;
  int posts = 0;
  final List<String> bearerTokens = <String>[];
  final List<String> postedIdTokens = <String>[];

  @override
  Future<OnboardCallResult> getCurrentUser({
    required String backendId,
    required String accessToken,
  }) async {
    gets += 1;
    bearerTokens.add(accessToken);
    return getStatus < 0
        ? const OnboardCallResult.transportError()
        : OnboardCallResult(getStatus);
  }

  @override
  Future<OnboardCallResult> createUser({
    required String backendId,
    required String accessToken,
    required String idToken,
  }) async {
    posts += 1;
    postedIdTokens.add(idToken);
    return postStatus < 0
        ? const OnboardCallResult.transportError()
        : OnboardCallResult(postStatus);
  }
}

Map<String, Object?> _registered({String? appClaim}) => <String, Object?>{
  'platform_service': 'true',
  if (appClaim case final String value) 'configuration_id': value,
};

BackendRegistration _registration({
  String backendId = 'primary',
  List<ResourceKey> resources = const <ResourceKey>[_primaryApi],
  ResourceKey onboardingResource = _primaryApi,
  String? appClaim,
}) => BackendRegistration(
  backendId: backendId,
  resources: resources,
  onboardingResource: onboardingResource,
  appClaim: appClaim,
);

void main() {
  group('ResourceKey', () {
    test('derives the C0 §8 audience and claim key', () {
      expect(
        _primaryApi.audience,
        'https://api.service.platform.lapras.cluster.atomi.cloud',
      );
      expect(_primaryApi.registrationClaim, 'platform_service');
      expect(_primaryApi.mapKey, 'platform/lapras/service/api');
    });

    test('lowercases and underscores the claim key', () {
      const ResourceKey key = ResourceKey(
        platform: 'Platform-One',
        landscape: 'lapras',
        service: 'billing-service',
        resourceName: 'api',
      );
      expect(key.registrationClaim, 'platform_one_billing_service');
    });
  });

  group('exact registration claim (S20)', () {
    test('only the JSON string "true" counts as present', () {
      ResourceToken token(Object? value) => ResourceToken(
        raw: 'raw',
        claims: <String, Object?>{'platform_service': value},
        expiresAt: DateTime.utc(2026),
      );

      expect(token('true').hasExactRegistrationClaim('platform_service'), true);
      expect(token(true).hasExactRegistrationClaim('platform_service'), false);
      expect(token('True').hasExactRegistrationClaim('platform_service'), false);
      expect(token(null).hasExactRegistrationClaim('platform_service'), false);
      expect(token(1).hasExactRegistrationClaim('platform_service'), false);
      expect(
        ResourceToken(
          raw: 'raw',
          claims: const <String, Object?>{},
          expiresAt: DateTime.utc(2026),
        ).hasExactRegistrationClaim('platform_service'),
        false,
        reason: 'a missing claim key counts as absent',
      );
    });
  });

  test('claims present on every token goes straight to ready', () async {
    final _Tokens tokens = _Tokens(
      claimsBefore: <ResourceKey, Map<String, Object?>>{
        _primaryApi: _registered(),
        _primaryFiles: _registered(),
      },
    );
    final _Client client = _Client();
    final BackendPhaseMachine machine = BackendPhaseMachine(
      registration: _registration(
        resources: <ResourceKey>[_primaryApi, _primaryFiles],
      ),
      tokens: tokens,
      client: client,
    );

    expect(await machine.run(), BackendPhase.ready);
    expect(client.gets, 0, reason: 'a present claim needs no probe (S20)');
    expect(client.posts, 0);
    expect(tokens.refreshes, 0);
    expect(machine.trace, <String>[
      'bootstrapping',
      'batch:2',
      'claims-present',
      'ready',
    ]);
  });

  test('an absent claim probes, creates on 404, then re-checks', () async {
    final _Tokens tokens = _Tokens(
      claimsBefore: <ResourceKey, Map<String, Object?>>{
        _primaryApi: const <String, Object?>{},
      },
      claimsAfter: <ResourceKey, Map<String, Object?>>{
        _primaryApi: _registered(),
      },
    );
    final _Client client = _Client();
    final BackendPhaseMachine machine = BackendPhaseMachine(
      registration: _registration(),
      tokens: tokens,
      client: client,
    );

    expect(await machine.run(), BackendPhase.ready);
    expect(client.gets, 1);
    expect(client.posts, 1);
    expect(client.postedIdTokens.single, 'raw-id-token');
    expect(tokens.refreshes, 1, reason: 'the re-check refresh is mandatory');
    expect(
      machine.trace,
      containsAllInOrder(<String>[
        'claims-absent',
        'get:404',
        'post:201',
        'refresh:1',
        'claims-repaired',
        'ready',
      ]),
    );
  });

  test('409 from POST /User is create-or-ok, never a failure', () async {
    final _Tokens tokens = _Tokens(
      claimsBefore: <ResourceKey, Map<String, Object?>>{
        _primaryApi: const <String, Object?>{},
      },
      claimsAfter: <ResourceKey, Map<String, Object?>>{
        _primaryApi: _registered(),
      },
    );
    final _Client client = _Client(postStatus: 409);
    final BackendPhaseMachine machine = BackendPhaseMachine(
      registration: _registration(),
      tokens: tokens,
      client: client,
    );

    expect(
      await machine.run(),
      BackendPhase.ready,
      reason: 'a concurrent first-sign-in race must not fail onboarding',
    );
    expect(machine.problem, isNull);
    expect(client.posts, 1);
    expect(machine.trace, contains('post:409'));
  });

  test('GET 200 skips create and still forces the re-check', () async {
    final _Tokens tokens = _Tokens(
      claimsBefore: <ResourceKey, Map<String, Object?>>{
        _primaryApi: const <String, Object?>{},
      },
      claimsAfter: <ResourceKey, Map<String, Object?>>{
        _primaryApi: _registered(),
      },
    );
    final _Client client = _Client(getStatus: 200);
    final BackendPhaseMachine machine = BackendPhaseMachine(
      registration: _registration(),
      tokens: tokens,
      client: client,
    );

    expect(await machine.run(), BackendPhase.ready);
    expect(client.posts, 0);
    expect(tokens.refreshes, 1);
  });

  test('a claim still absent after refresh is OnboardingClaimMissing', () async {
    final _Tokens tokens = _Tokens(
      claimsBefore: <ResourceKey, Map<String, Object?>>{
        _primaryApi: const <String, Object?>{},
      },
    );
    final BackendPhaseMachine machine = BackendPhaseMachine(
      registration: _registration(),
      tokens: tokens,
      client: _Client(),
    );

    expect(await machine.run(), BackendPhase.error);
    expect(machine.problem!.type, 'urn:diene:problem:onboarding-claim-missing');
    expect(tokens.refreshes, 1);
  });

  test('a 404 with no ID token available is an error, not a POST', () async {
    final _Client client = _Client();
    final BackendPhaseMachine machine = BackendPhaseMachine(
      registration: _registration(),
      tokens: _Tokens(
        claimsBefore: <ResourceKey, Map<String, Object?>>{
          _primaryApi: const <String, Object?>{},
        },
        idTokenValue: null,
      ),
      client: client,
    );

    expect(await machine.run(), BackendPhase.error);
    expect(machine.problem!.type, 'urn:diene:problem:id-token-missing');
    expect(client.posts, 0, reason: 'POST /User requires the raw ID token');
  });

  test('a non-404, non-200 probe is an error with no create', () async {
    final _Client client = _Client(getStatus: 500);
    final BackendPhaseMachine machine = BackendPhaseMachine(
      registration: _registration(),
      tokens: _Tokens(
        claimsBefore: <ResourceKey, Map<String, Object?>>{
          _primaryApi: const <String, Object?>{},
        },
      ),
      client: client,
    );

    expect(await machine.run(), BackendPhase.error);
    expect(client.posts, 0);
    expect(machine.problem!.type, 'urn:diene:problem:onboard-probe');
  });

  test('an incomplete token batch is an error, not a silent pass', () async {
    final BackendPhaseMachine machine = BackendPhaseMachine(
      registration: _registration(
        resources: <ResourceKey>[_primaryApi, _primaryFiles],
      ),
      tokens: _Tokens(
        claimsBefore: <ResourceKey, Map<String, Object?>>{
          _primaryApi: _registered(),
          _primaryFiles: _registered(),
        },
        omit: <ResourceKey>{_primaryFiles},
      ),
      client: _Client(),
    );

    expect(await machine.run(), BackendPhase.error);
    expect(machine.problem!.type, 'urn:diene:problem:token-batch-incomplete');
  });

  test('a registered backend missing its app claim needs onboarding', () async {
    final BackendPhaseMachine machine = BackendPhaseMachine(
      registration: _registration(appClaim: 'configuration_id'),
      tokens: _Tokens(
        claimsBefore: <ResourceKey, Map<String, Object?>>{
          _primaryApi: _registered(),
        },
      ),
      client: _Client(),
    );

    expect(await machine.run(), BackendPhase.needsOnboarding);
  });

  test('the app claim present makes it ready', () async {
    final BackendPhaseMachine machine = BackendPhaseMachine(
      registration: _registration(appClaim: 'configuration_id'),
      tokens: _Tokens(
        claimsBefore: <ResourceKey, Map<String, Object?>>{
          _primaryApi: _registered(appClaim: 'config-1'),
        },
      ),
      client: _Client(),
    );

    expect(await machine.run(), BackendPhase.ready);
  });

  test('a stale claim never re-runs detection (C0 §8 step 5)', () async {
    final _Client client = _Client();
    final BackendPhaseMachine machine = BackendPhaseMachine(
      registration: _registration(),
      tokens: _Tokens(
        claimsBefore: <ResourceKey, Map<String, Object?>>{
          _primaryApi: _registered(),
        },
      ),
      client: client,
    );
    expect(await machine.run(), BackendPhase.ready);

    expect(machine.reportOwnedResourceStatus(401), BackendPhase.error);
    expect(machine.problem!.type, 'urn:diene:problem:stale-claim');
    expect(client.gets, 0, reason: 'a stale claim is not a second detector');
    expect(client.posts, 0);
  });

  group('multi-backend independence', () {
    test('ready on A while B still needs onboarding', () async {
      final BackendPhaseMachine backendA = BackendPhaseMachine(
        registration: _registration(backendId: 'alpha'),
        tokens: _Tokens(
          claimsBefore: <ResourceKey, Map<String, Object?>>{
            _primaryApi: _registered(),
          },
        ),
        client: _Client(),
      );
      final BackendPhaseMachine backendB = BackendPhaseMachine(
        registration: BackendRegistration(
          backendId: 'beta',
          resources: const <ResourceKey>[_secondaryApi],
          onboardingResource: _secondaryApi,
          appClaim: 'configuration_id',
        ),
        tokens: _Tokens(
          claimsBefore: <ResourceKey, Map<String, Object?>>{
            _secondaryApi: const <String, Object?>{
              'platform_billing_service': 'true',
            },
          },
        ),
        client: _Client(),
      );
      final OnboardingPhaseMachineSet set = OnboardingPhaseMachineSet(
        <BackendPhaseMachine>[backendA, backendB],
      );

      final Map<String, BackendPhase> phases = await set.runAll();

      expect(phases, <String, BackendPhase>{
        'alpha': BackendPhase.ready,
        'beta': BackendPhase.needsOnboarding,
      });
      // The route gate keys only to the backends it declares.
      expect(set.isReadyFor(<String>['alpha']), isTrue);
      expect(set.isReadyFor(<String>['beta']), isFalse);
      expect(set.isReadyFor(<String>['alpha', 'beta']), isFalse);
    });

    test('an error on B leaves A ready — no fleet-wide failure', () async {
      final BackendPhaseMachine backendA = BackendPhaseMachine(
        registration: _registration(backendId: 'alpha'),
        tokens: _Tokens(
          claimsBefore: <ResourceKey, Map<String, Object?>>{
            _primaryApi: _registered(),
          },
        ),
        client: _Client(),
      );
      final BackendPhaseMachine backendB = BackendPhaseMachine(
        registration: BackendRegistration(
          backendId: 'beta',
          resources: const <ResourceKey>[_secondaryApi],
          onboardingResource: _secondaryApi,
        ),
        tokens: _Tokens(
          claimsBefore: <ResourceKey, Map<String, Object?>>{
            _secondaryApi: const <String, Object?>{},
          },
          failing: <ResourceKey>{_secondaryApi},
        ),
        client: _Client(),
      );
      final OnboardingPhaseMachineSet set = OnboardingPhaseMachineSet(
        <BackendPhaseMachine>[backendA, backendB],
      );

      final Map<String, BackendPhase> phases = await set.runAll();

      expect(phases['alpha'], BackendPhase.ready);
      expect(phases['beta'], BackendPhase.error);
      expect(set.isReadyFor(<String>['alpha']), isTrue);
    });

    test('there is no singleton onboarded flag', () async {
      final OnboardingPhaseMachineSet set = OnboardingPhaseMachineSet(
        <BackendPhaseMachine>[
          BackendPhaseMachine(
            registration: _registration(backendId: 'alpha'),
            tokens: _Tokens(
              claimsBefore: <ResourceKey, Map<String, Object?>>{
                _primaryApi: _registered(),
              },
            ),
            client: _Client(),
          ),
        ],
      );
      await set.runAll();

      // Being ready on alpha says nothing about an unregistered backend.
      expect(set.isReadyFor(<String>['gamma']), isFalse);
    });
  });
}
