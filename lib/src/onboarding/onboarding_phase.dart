import '../auth/auth_seam.dart';
import '../auth/claims.dart';
import '../contracts/problem.dart';
import '../contracts/result.dart';
import '../tokens/resource_key.dart';
import '../tokens/session_tokens.dart';
import 'backend_registry.dart';
import 'user_directory.dart';

/// Per-backend claims-first phase (C0 §8 S20). NO singleton onboarded flag —
/// one machine per registered backend.
enum OnboardingPhase { bootstrapping, needsOnboarding, ready, error }

/// Reads the raw OIDC ID token for the `POST /User` create body.
typedef IdTokenReader = Future<String?> Function();

/// Drives ONE backend through the C0 §8 claims-first state table. Failure is
/// isolated to this backend; disjoint backends run their own machines.
final class OnboardingMachine {
  OnboardingMachine({
    required RegisteredBackend backend,
    required IAuth auth,
    required UserDirectory directory,
    required IdTokenReader idToken,
  }) : _backend = backend,
       _auth = auth,
       _directory = directory,
       _idToken = idToken;

  final RegisteredBackend _backend;
  final IAuth _auth;
  final UserDirectory _directory;
  final IdTokenReader _idToken;

  OnboardingPhase _phase = OnboardingPhase.bootstrapping;
  OnboardingPhase get phase => _phase;

  String get backendId => _backend.backendId;

  /// This backend's required resource keys (used by [MultiBackendOnboarding] to
  /// project the shared registry-union batch).
  List<ResourceKey> get resources => _backend.resources;

  /// Runs the machine to a terminal phase for this backend.
  ///
  /// [initialBatch] is this backend's projection of the ONE
  /// registry-union acquisition (C0 §8) taken by [MultiBackendOnboarding]. When
  /// omitted (a standalone single-backend run) the machine acquires its own
  /// batch. Either way the create-path force-refresh below re-acquires ONLY this
  /// backend's resources.
  Future<Result<OnboardingPhase>> run({
    Map<ResourceKey, Result<ResourceToken>>? initialBatch,
  }) async {
    _phase = OnboardingPhase.bootstrapping;
    // Step 1: resolve the backend's complete token batch — the shared
    // registry-union projection when supplied, else a scoped acquisition.
    final Map<ResourceKey, Result<ResourceToken>> batch =
        initialBatch ?? await _auth.fetchAllTokens(_backend.resources);
    final Problem? batchProblem = _firstFailure(batch);
    if (batchProblem != null) {
      return _error(batchProblem);
    }

    // Step 2: registered on every required resource token?
    if (_allRegistered(batch)) {
      return _settleRegistered(batch);
    }

    // Step 3: registration absent from ANY token → one GET /User/Me.
    final ResourceToken onboarding =
        (batch[_backend.onboardingResource]! as Success<ResourceToken>).value;
    try {
      final int getStatus = await _directory.getUserMe(
        backendId: _backend.backendId,
        accessToken: onboarding.token,
      );
      if (getStatus == 404) {
        final String? idToken = await _idToken();
        if (idToken == null) {
          return _error(
            const Problem(
              type: 'urn:diene:problem:onboarding-idtoken',
              title: 'Missing ID token for onboarding create',
              status: 401,
            ),
          );
        }
        final int postStatus = await _directory.postUser(
          backendId: _backend.backendId,
          accessToken: onboarding.token,
          idToken: idToken,
        );
        final bool createdOrOk =
            (postStatus >= 200 && postStatus < 300) || postStatus == 409;
        if (!createdOrOk) {
          return _error(_httpProblem('POST /User', postStatus));
        }
      } else if (getStatus != 200) {
        return _error(_httpProblem('GET /User/Me', getStatus));
      }
    } on Object catch (error) {
      return _error(
        Problem(
          type: 'urn:diene:problem:onboarding-transport',
          title: 'Onboarding request failed',
          status: 503,
          detail: error.toString(),
          recoverable: true,
        ),
      );
    }

    // Step 4: force-refresh ALL resource tokens and re-check the exact claim.
    for (final ResourceKey key in _backend.resources) {
      _auth.invalidate(key);
    }
    final Map<ResourceKey, Result<ResourceToken>> refreshed = await _auth
        .fetchAllTokens(_backend.resources);
    final Problem? refreshProblem = _firstFailure(refreshed);
    if (refreshProblem != null) {
      return _error(refreshProblem);
    }
    if (_allRegistered(refreshed)) {
      return _settleRegistered(refreshed);
    }
    // Still absent after the create/refresh: the only claim-repair path failed.
    return _error(
      const Problem(
        type: 'urn:diene:problem:onboarding-claim-missing',
        title: 'OnboardingClaimMissing',
        status: 409,
      ),
    );
  }

  /// Step 5: a claim was present but a normal owned-resource call later
  /// returned 401/404. This is an ordinary authorization/data error — enter
  /// `error` WITHOUT re-running `/User/Me` or create.
  Result<OnboardingPhase> markStaleClaim() => _error(
    const Problem(
      type: 'urn:diene:problem:onboarding-stale-claim',
      title: 'Stale onboarding claim',
      status: 401,
    ),
  );

  Result<OnboardingPhase> _settleRegistered(
    Map<ResourceKey, Result<ResourceToken>> batch,
  ) {
    final String? appClaim = _backend.appOnboardingClaim;
    if (appClaim != null) {
      final ResourceToken onboarding =
          (batch[_backend.onboardingResource]! as Success<ResourceToken>).value;
      final Map<String, Object?> claims = Claims.decode(onboarding.token);
      final Object? value = claims[appClaim];
      final bool present = value is String && value == 'true';
      if (!present) {
        _phase = OnboardingPhase.needsOnboarding;
        return Success<OnboardingPhase>(_phase);
      }
    }
    _phase = OnboardingPhase.ready;
    return Success<OnboardingPhase>(_phase);
  }

  bool _allRegistered(Map<ResourceKey, Result<ResourceToken>> batch) {
    for (final ResourceKey key in _backend.resources) {
      final ResourceToken token = (batch[key]! as Success<ResourceToken>).value;
      final Map<String, Object?> claims = Claims.decode(token.token);
      if (!Claims.hasRegistration(
        claims,
        platform: key.platform,
        service: key.service,
      )) {
        return false;
      }
    }
    return true;
  }

  Problem? _firstFailure(Map<ResourceKey, Result<ResourceToken>> batch) {
    for (final Result<ResourceToken> result in batch.values) {
      if (result is Failure<ResourceToken>) {
        return result.problem;
      }
    }
    return null;
  }

  Problem _httpProblem(String call, int status) => Problem(
    type: 'urn:diene:problem:onboarding-http',
    title: 'Onboarding call failed',
    status: status,
    detail: '$call returned $status',
    data: <String, Object?>{'call': call, 'status': status},
  );

  Result<OnboardingPhase> _error(Problem problem) {
    _phase = OnboardingPhase.error;
    return Failure<OnboardingPhase>(problem);
  }
}

/// Holds one [OnboardingMachine] per registered backend — independent phases,
/// no cross-backend state bleed (ready on A while onboarding/error on B).
final class MultiBackendOnboarding {
  MultiBackendOnboarding({
    required BackendRegistry registry,
    required IAuth auth,
    required UserDirectory directory,
    required IdTokenReader idToken,
  }) : _registry = registry,
       _auth = auth,
       _machines = <String, OnboardingMachine>{
         for (final RegisteredBackend backend in registry.backends)
           backend.backendId: OnboardingMachine(
             backend: backend,
             auth: auth,
             directory: directory,
             idToken: idToken,
           ),
       };

  final BackendRegistry _registry;
  final IAuth _auth;
  final Map<String, OnboardingMachine> _machines;

  OnboardingMachine machineFor(String backendId) {
    final OnboardingMachine? machine = _machines[backendId];
    if (machine == null) {
      throw ArgumentError.value(backendId, 'backendId', 'unregistered backend');
    }
    return machine;
  }

  /// Current phase per backend.
  Map<String, OnboardingPhase> get phases => <String, OnboardingPhase>{
    for (final MapEntry<String, OnboardingMachine> entry in _machines.entries)
      entry.key: entry.value.phase,
  };

  /// Bootstraps every backend from ONE registry-union acquisition (C0 §8):
  /// takes a single registry snapshot, deduplicates the full `ResourceKey`
  /// union, starts exactly one initial acquisition batch, and projects it into
  /// independent per-backend outcomes. A resource shared by two backends is
  /// acquired once here — never once per backend. Each backend's terminal phase
  /// stays independent, and the create-path force-refresh inside each machine
  /// re-acquires only that backend's resources.
  Future<Map<String, Result<OnboardingPhase>>> runAll() async {
    // One snapshot + dedup union + one initial acquisition batch.
    final List<ResourceKey> union = _registry.resourceUnion;
    final Map<ResourceKey, Result<ResourceToken>> unionBatch = await _auth
        .fetchAllTokens(union);

    // Project the single batch into each backend's slice and run concurrently.
    final Map<String, Future<Result<OnboardingPhase>>> started =
        <String, Future<Result<OnboardingPhase>>>{
          for (final MapEntry<String, OnboardingMachine> entry
              in _machines.entries)
            entry.key: entry.value.run(
              initialBatch: _project(entry.value, unionBatch),
            ),
        };
    final Map<String, Result<OnboardingPhase>> results =
        <String, Result<OnboardingPhase>>{};
    for (final MapEntry<String, Future<Result<OnboardingPhase>>> entry
        in started.entries) {
      results[entry.key] = await entry.value;
    }
    return results;
  }

  /// Slices the shared [unionBatch] down to one machine's required resources.
  Map<ResourceKey, Result<ResourceToken>> _project(
    OnboardingMachine machine,
    Map<ResourceKey, Result<ResourceToken>> unionBatch,
  ) => <ResourceKey, Result<ResourceToken>>{
    for (final ResourceKey key in machine.resources)
      if (unionBatch.containsKey(key)) key: unionBatch[key]!,
  };
}
