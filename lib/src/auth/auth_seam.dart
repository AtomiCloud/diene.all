import 'dart:async';

import '../contracts/problem.dart';
import '../contracts/result.dart';
import '../tokens/resource_key.dart';
import '../tokens/session_tokens.dart';
import 'auth_provider.dart';

/// The retriever seam api-engine dogfoods: resolve a token per resource with a
/// per-resource cache in front of the hot path, plus the eager all-token batch
/// (C0 §8, S7).
abstract interface class IAuth {
  /// Resolves one resource's token, serving the cache when still valid.
  Future<Result<ResourceToken>> tokenFor(ResourceKey key);

  /// Eager all-token batch: dedups [keys] by full [ResourceKey], starts
  /// acquisition for EVERY key before awaiting any, and returns a total map
  /// with exactly one terminal entry per requested key. Lazy first-call
  /// acquisition is not permitted.
  Future<Map<ResourceKey, Result<ResourceToken>>> fetchAllTokens(
    Iterable<ResourceKey> keys,
  );

  /// Drops every cached resource token (used on sign-out / force-refresh).
  void invalidateAll();

  /// Drops one resource's cached token.
  void invalidate(ResourceKey key);
}

/// A clock skew applied when deciding whether a cached token is still fresh.
const Duration _refreshSkew = Duration(seconds: 30);

/// Default [IAuth] implementation: cache keyed per [ResourceKey], expiry-aware
/// refresh, and single-flight refresh-race handling (concurrent callers for the
/// same key await ONE acquisition).
final class AuthCoordinator implements IAuth {
  AuthCoordinator({required AuthProvider provider, DateTime Function()? now})
    : _provider = provider,
      _now = now ?? DateTime.now;

  final AuthProvider _provider;
  final DateTime Function() _now;
  final Map<String, ResourceToken> _cache = <String, ResourceToken>{};
  final Map<String, Future<Result<ResourceToken>>> _inflight =
      <String, Future<Result<ResourceToken>>>{};

  @override
  Future<Result<ResourceToken>> tokenFor(ResourceKey key) {
    final DateTime now = _now().toUtc();
    final ResourceToken? cached = _cache[key.mapKey];
    if (cached != null && cached.expiresAt.isAfter(now.add(_refreshSkew))) {
      return Future<Result<ResourceToken>>.value(
        Success<ResourceToken>(cached),
      );
    }
    // Single-flight: concurrent callers for the same key share one acquisition.
    final Future<Result<ResourceToken>>? pending = _inflight[key.mapKey];
    if (pending != null) {
      return pending;
    }
    final Future<Result<ResourceToken>> acquisition = _acquire(key);
    _inflight[key.mapKey] = acquisition;
    return acquisition.whenComplete(() => _inflight.remove(key.mapKey));
  }

  Future<Result<ResourceToken>> _acquire(ResourceKey key) async {
    try {
      final ResourceToken token = await _provider.resourceToken(key);
      _cache[key.mapKey] = token;
      return Success<ResourceToken>(token);
    } on Object catch (error) {
      return Failure<ResourceToken>(
        Problem(
          type: 'urn:diene:problem:resource-token',
          title: 'Could not acquire a resource token',
          status: 401,
          detail: error.toString(),
          recoverable: true,
          data: <String, Object?>{'resource': key.mapKey},
        ),
      );
    }
  }

  @override
  Future<Map<ResourceKey, Result<ResourceToken>>> fetchAllTokens(
    Iterable<ResourceKey> keys,
  ) async {
    // Deduplicate the union by full ResourceKey (mapKey identity).
    final Map<String, ResourceKey> unique = <String, ResourceKey>{};
    for (final ResourceKey key in keys) {
      unique[key.mapKey] = key;
    }
    // Start EVERY acquisition before awaiting any (no lazy first-call).
    final Map<ResourceKey, Future<Result<ResourceToken>>> started =
        <ResourceKey, Future<Result<ResourceToken>>>{
          for (final ResourceKey key in unique.values) key: tokenFor(key),
        };
    final Map<ResourceKey, Result<ResourceToken>> results =
        <ResourceKey, Result<ResourceToken>>{};
    for (final MapEntry<ResourceKey, Future<Result<ResourceToken>>> entry
        in started.entries) {
      results[entry.key] = await entry.value;
    }
    return results;
  }

  @override
  void invalidate(ResourceKey key) => _cache.remove(key.mapKey);

  @override
  void invalidateAll() => _cache.clear();
}
