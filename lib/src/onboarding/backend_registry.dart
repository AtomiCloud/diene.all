import 'package:meta/meta.dart';

import '../tokens/resource_key.dart';

/// One registered backend in the client tree (C0 §8).
///
/// One client app onboards to MANY backends; each declares its stable
/// [backendId], the full [resources] it needs, and which one
/// ([onboardingResource]) protects its `/User` onboarding surface.
@immutable
final class RegisteredBackend {
  RegisteredBackend({
    required this.backendId,
    required this.resources,
    required this.onboardingResource,
    this.appOnboardingClaim,
  }) {
    if (backendId.isEmpty) {
      throw ArgumentError.value(backendId, 'backendId', 'must be non-empty');
    }
    if (resources.isEmpty) {
      throw ArgumentError.value(
        resources,
        'resources',
        'a backend must require at least one resource',
      );
    }
    if (!resources.any((ResourceKey r) => r == onboardingResource)) {
      throw ArgumentError.value(
        onboardingResource,
        'onboardingResource',
        'must be one of the declared resources',
      );
    }
  }

  /// Stable identifier used to key per-backend phase state.
  final String backendId;

  /// The full resource keys this backend needs.
  final List<ResourceKey> resources;

  /// The resource whose token protects the `/User` onboarding surface.
  final ResourceKey onboardingResource;

  /// A separately declared app-specific onboarding claim name; when set and
  /// absent from the onboarding-resource token, the backend is
  /// `needsOnboarding` even though it is registered.
  final String? appOnboardingClaim;
}

/// The set of backends a client is wired to. Backend ids are unique.
final class BackendRegistry {
  BackendRegistry(Iterable<RegisteredBackend> backends) {
    for (final RegisteredBackend backend in backends) {
      if (_byId.containsKey(backend.backendId)) {
        throw ArgumentError.value(
          backend.backendId,
          'backendId',
          'duplicate backend id',
        );
      }
      _byId[backend.backendId] = backend;
    }
  }

  final Map<String, RegisteredBackend> _byId = <String, RegisteredBackend>{};

  Iterable<RegisteredBackend> get backends => _byId.values;

  RegisteredBackend? byId(String backendId) => _byId[backendId];

  /// The deduplicated union of every backend's resource keys — the snapshot the
  /// all-token batch acquires (C0 §8 S7).
  List<ResourceKey> get resourceUnion {
    final Map<String, ResourceKey> unique = <String, ResourceKey>{};
    for (final RegisteredBackend backend in _byId.values) {
      for (final ResourceKey key in backend.resources) {
        unique[key.mapKey] = key;
      }
    }
    return unique.values.toList(growable: false);
  }
}
