/// Per-backend, claims-first onboarding phase machine (C0 §8, S20;
/// goals/authorization-pattern.md "Onboarding (OnboardSync)").
///
/// There is NO singleton onboarded flag. Every registered backend owns an
/// independent phase, so being ready on backend A says nothing about backend
/// B. Readiness is read from the per-resource ACCESS TOKEN claims; the
/// `GET /User/Me` probe exists only as create-time race handling after an
/// absent claim, and a 409 from `POST /User` is create-or-ok, never a failure.
library;

import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

/// The four phases a single backend can be in (C0 §8).
enum BackendPhase { bootstrapping, needsOnboarding, ready, error }

/// A full resource identity (C0 §8, S7):
/// `(platform, landscape, service, resourceName)`.
final class ResourceKey {
  const ResourceKey({
    required this.platform,
    required this.landscape,
    required this.service,
    required this.resourceName,
  });

  final String platform;
  final String landscape;
  final String service;
  final String resourceName;

  /// Canonical client-map key `platform/landscape/service/resourceName`.
  String get mapKey => '$platform/$landscape/$service/$resourceName';

  /// The Logto resource identifier / JWT `aud`, with no trailing slash.
  String get audience =>
      'https://$resourceName.$service.$platform.$landscape.cluster.atomi.cloud';

  /// The exact registration claim key: `<platform>_<service>`, lowercased with
  /// every `-` replaced by `_` (C0 §8, S20).
  String get registrationClaim =>
      '${platform.toLowerCase().replaceAll('-', '_')}_'
      '${service.toLowerCase().replaceAll('-', '_')}';

  @override
  bool operator ==(Object other) =>
      other is ResourceKey && other.mapKey == mapKey;

  @override
  int get hashCode => mapKey.hashCode;

  @override
  String toString() => mapKey;
}

/// An access token plus its decoded claims.
final class ResourceToken {
  const ResourceToken({
    required this.raw,
    required this.claims,
    required this.expiresAt,
  });

  final String raw;
  final Map<String, Object?> claims;
  final DateTime expiresAt;

  /// True only for the exact JSON string `"true"` — missing, null, boolean
  /// `true`, or anything else counts as ABSENT (C0 §8, S20).
  bool hasExactRegistrationClaim(String claimKey) => claims[claimKey] == 'true';
}

/// One registered backend and the resources it needs.
final class BackendRegistration {
  const BackendRegistration({
    required this.backendId,
    required this.resources,
    required this.onboardingResource,
    this.appClaim,
  });

  final String backendId;

  /// Every full resource key this backend needs. Must contain
  /// [onboardingResource].
  final List<ResourceKey> resources;

  /// The resource whose token protects the `/User` onboarding surface.
  final ResourceKey onboardingResource;

  /// An extra app-specific onboarding claim (alcohol's `configuration_id`
  /// analogue). Absent → `needsOnboarding` even once registered.
  final String? appClaim;
}

/// Acquires per-resource tokens through the IAuth seam.
abstract interface class TokenProvider {
  /// Acquires every key in one batch. The returned map is TOTAL: exactly one
  /// terminal entry per requested key (C0 §8 all-token batch).
  Future<Map<ResourceKey, Result<ResourceToken>>> acquireAll(
    Set<ResourceKey> keys, {
    bool forceRefresh = false,
  });

  /// The raw ID token, sent in the `POST /User` body.
  Future<String?> idToken();
}

/// Outcome of one `GET /User/Me` or `POST /User` call. `status` is the HTTP
/// status; a transport failure is reported as [OnboardCallResult.transportError].
final class OnboardCallResult {
  const OnboardCallResult(this.status);

  const OnboardCallResult.transportError() : status = -1;

  final int status;

  bool get isTransportError => status < 0;
}

/// The `/User` surface of one backend.
abstract interface class OnboardSyncClient {
  /// `GET /User/Me` with the onboarding-resource bearer token.
  Future<OnboardCallResult> getCurrentUser({
    required String backendId,
    required String accessToken,
  });

  /// `POST /User` with the bearer header and body
  /// `{idToken, accessToken}` (C0 §8 step 3).
  Future<OnboardCallResult> createUser({
    required String backendId,
    required String accessToken,
    required String idToken,
  });
}

/// The phase machine for exactly ONE backend.
final class BackendPhaseMachine {
  BackendPhaseMachine({
    required this.registration,
    required this.tokens,
    required this.client,
  });

  final BackendRegistration registration;
  final TokenProvider tokens;
  final OnboardSyncClient client;

  BackendPhase _phase = BackendPhase.bootstrapping;
  Problem? _problem;

  /// Ordered trace of what this machine did — the evidence the unit tests
  /// assert on.
  final List<String> trace = <String>[];

  BackendPhase get phase => _phase;
  Problem? get problem => _problem;
  String get backendId => registration.backendId;

  Future<BackendPhase> run() async {
    _phase = BackendPhase.bootstrapping;
    _problem = null;
    trace.add('bootstrapping');

    final Set<ResourceKey> keys = registration.resources.toSet();
    Map<ResourceKey, Result<ResourceToken>> batch = await tokens.acquireAll(
      keys,
    );
    trace.add('batch:${batch.length}');
    if (!_batchIsTotal(batch, keys)) {
      return _fail(
        'urn:diene:problem:token-batch-incomplete',
        'Token batch did not cover every required resource',
      );
    }
    final Map<ResourceKey, ResourceToken>? resolved = _unwrap(batch);
    if (resolved == null) {
      return _fail(
        'urn:diene:problem:token-acquisition',
        'A required resource token could not be acquired',
      );
    }

    if (_allRegistered(resolved)) {
      trace.add('claims-present');
      return _afterRegistration(resolved);
    }
    trace.add('claims-absent');

    final ResourceToken onboardingToken =
        resolved[registration.onboardingResource]!;
    final OnboardCallResult probe = await client.getCurrentUser(
      backendId: registration.backendId,
      accessToken: onboardingToken.raw,
    );
    trace.add('get:${probe.status}');
    if (probe.isTransportError) {
      return _fail(
        'urn:diene:problem:onboard-probe',
        'Could not probe the current user',
      );
    }
    if (probe.status == 404) {
      final String? id = await tokens.idToken();
      if (id == null) {
        return _fail(
          'urn:diene:problem:id-token-missing',
          'The ID token required by POST /User is missing',
        );
      }
      final OnboardCallResult created = await client.createUser(
        backendId: registration.backendId,
        accessToken: onboardingToken.raw,
        idToken: id,
      );
      trace.add('post:${created.status}');
      // create-or-ok: any 2xx OR 409 is success. Treating 409 as a failure is
      // the sabotage this gate catches.
      final bool createdOrOk =
          (created.status >= 200 && created.status < 300) ||
          created.status == 409;
      if (!createdOrOk) {
        return _fail(
          'urn:diene:problem:onboard-create',
          'POST /User failed with status ${created.status}',
        );
      }
    } else if (probe.status != 200) {
      return _fail(
        'urn:diene:problem:onboard-probe',
        'GET /User/Me failed with status ${probe.status}',
      );
    }

    // Mandatory force-refresh + re-check. This is the ONLY claim-repair path.
    batch = await tokens.acquireAll(keys, forceRefresh: true);
    trace.add('refresh:${batch.length}');
    if (!_batchIsTotal(batch, keys)) {
      return _fail(
        'urn:diene:problem:token-batch-incomplete',
        'Refreshed token batch did not cover every required resource',
      );
    }
    final Map<ResourceKey, ResourceToken>? refreshed = _unwrap(batch);
    if (refreshed == null) {
      return _fail(
        'urn:diene:problem:token-acquisition',
        'A required resource token could not be refreshed',
      );
    }
    if (!_allRegistered(refreshed)) {
      return _fail(
        'urn:diene:problem:onboarding-claim-missing',
        'OnboardingClaimMissing: the registration claim is still absent',
      );
    }
    trace.add('claims-repaired');
    return _afterRegistration(refreshed);
  }

  /// A previously-registered backend that later gets a 401/404 on an ordinary
  /// owned-resource call enters `error`. It MUST NOT re-probe or re-create
  /// (C0 §8 step 5) — a stale claim is an ordinary authorization error.
  BackendPhase reportOwnedResourceStatus(int status) {
    if (status != 401 && status != 404) {
      return _phase;
    }
    trace.add('stale-claim:$status');
    return _fail(
      'urn:diene:problem:stale-claim',
      'Owned-resource call returned $status; re-detection is forbidden',
    );
  }

  bool _batchIsTotal(
    Map<ResourceKey, Result<ResourceToken>> batch,
    Set<ResourceKey> keys,
  ) => keys.every(batch.containsKey) && batch.length == keys.length;

  Map<ResourceKey, ResourceToken>? _unwrap(
    Map<ResourceKey, Result<ResourceToken>> batch,
  ) {
    final Map<ResourceKey, ResourceToken> resolved =
        <ResourceKey, ResourceToken>{};
    for (final MapEntry<ResourceKey, Result<ResourceToken>> entry
        in batch.entries) {
      final Result<ResourceToken> value = entry.value;
      if (value is! Ok<ResourceToken>) {
        return null;
      }
      resolved[entry.key] = value.value;
    }
    return resolved;
  }

  bool _allRegistered(Map<ResourceKey, ResourceToken> resolved) =>
      registration.resources.every(
        (ResourceKey key) =>
            resolved[key]?.hasExactRegistrationClaim(key.registrationClaim) ??
            false,
      );

  BackendPhase _afterRegistration(Map<ResourceKey, ResourceToken> resolved) {
    final String? appClaim = registration.appClaim;
    if (appClaim != null) {
      final ResourceToken token = resolved[registration.onboardingResource]!;
      final Object? value = token.claims[appClaim];
      if (value == null || (value is String && value.isEmpty)) {
        _phase = BackendPhase.needsOnboarding;
        trace.add('needsOnboarding');
        return _phase;
      }
    }
    _phase = BackendPhase.ready;
    trace.add('ready');
    return _phase;
  }

  BackendPhase _fail(String type, String detail) {
    _phase = BackendPhase.error;
    _problem = Problem(
      type: type,
      title: 'Onboarding failed for ${registration.backendId}',
      status: 503,
      detail: detail,
      recoverable: true,
    );
    trace.add('error:$type');
    return _phase;
  }
}

/// A set of independent per-backend machines.
///
/// Backends never share state: one may be `ready` while another is
/// `needsOnboarding` or `error`.
final class OnboardingPhaseMachineSet {
  OnboardingPhaseMachineSet(this.machines);

  final List<BackendPhaseMachine> machines;

  Map<String, BackendPhase> get phases => <String, BackendPhase>{
    for (final BackendPhaseMachine machine in machines)
      machine.backendId: machine.phase,
  };

  /// Runs every backend machine. Failures are isolated per backend.
  Future<Map<String, BackendPhase>> runAll() async {
    for (final BackendPhaseMachine machine in machines) {
      await machine.run();
    }
    return phases;
  }

  /// True when every backend a route/module needs is `ready`. A route gates
  /// only on its declared backends — never on the whole fleet.
  bool isReadyFor(Iterable<String> requiredBackendIds) {
    final Map<String, BackendPhase> current = phases;
    return requiredBackendIds.every(
      (String id) => current[id] == BackendPhase.ready,
    );
  }
}
