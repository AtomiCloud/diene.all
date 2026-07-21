import '../auth/auth_provider.dart';
import '../auth/auth_seam.dart';
import '../contracts/problem.dart';
import '../contracts/result.dart';
import '../deferred/deferred_login.dart';
import '../deferred/redeem_client.dart';
import '../home/home_claim.dart';
import '../home/landscape_selector.dart';
import '../onboarding/user_directory.dart';
import '../tokens/resource_key.dart';
import '../tokens/session_tokens.dart';

/// Scriptable [AuthProvider] fake — drive token mint/refresh/failure without a
/// real IdP.
final class FakeAuthProvider implements AuthProvider {
  FakeAuthProvider({
    SessionTokens Function()? onSignIn,
    SessionTokens Function(SessionTokens current)? onRefresh,
    SessionTokens Function(SessionTokens current)? onReMint,
    Map<String, ResourceToken>? resourceTokens,
    String? idTokenValue,
    Object? throwOnSignIn,
  }) : _onSignIn = onSignIn,
       _onRefresh = onRefresh,
       _onReMint = onReMint,
       _resourceTokens = resourceTokens ?? <String, ResourceToken>{},
       _idTokenValue = idTokenValue,
       _throwOnSignIn = throwOnSignIn;

  final SessionTokens Function()? _onSignIn;
  final SessionTokens Function(SessionTokens current)? _onRefresh;
  final SessionTokens Function(SessionTokens current)? _onReMint;
  final Map<String, ResourceToken> _resourceTokens;
  final String? _idTokenValue;
  final Object? _throwOnSignIn;

  int signInCount = 0;
  int refreshCount = 0;
  int reMintCount = 0;
  int signOutCount = 0;
  Map<String, String> lastExtraParams = const <String, String>{};

  @override
  Future<SessionTokens> signIn({
    Map<String, String> extraParams = const <String, String>{},
  }) async {
    signInCount += 1;
    lastExtraParams = extraParams;
    if (_throwOnSignIn != null) {
      throw _throwOnSignIn;
    }
    return (_onSignIn ?? (() => throw StateError('no signIn scripted')))();
  }

  @override
  Future<SessionTokens> refresh(SessionTokens current) async {
    refreshCount += 1;
    return (_onRefresh ?? (SessionTokens c) => throw StateError('no refresh'))(
      current,
    );
  }

  @override
  Future<SessionTokens> reMintOnOpen(SessionTokens current) async {
    reMintCount += 1;
    return (_onReMint ?? (SessionTokens c) => throw StateError('no reMint'))(
      current,
    );
  }

  @override
  Future<void> signOut() async => signOutCount += 1;

  @override
  Future<ResourceToken> resourceToken(ResourceKey key) async {
    final ResourceToken? token = _resourceTokens[key.mapKey];
    if (token == null) {
      throw StateError('no resource token scripted for ${key.mapKey}');
    }
    return token;
  }

  @override
  Future<String?> idToken() async => _idTokenValue;
}

/// Scriptable [IAuth] fake. Successive [fetchAllTokens] calls return successive
/// [batches] (the last repeats), modelling the force-refresh claim-repair path.
final class FakeAuth implements IAuth {
  FakeAuth(this.batches)
    : assert(batches.isNotEmpty, 'at least one batch is required');

  final List<Map<ResourceKey, Result<ResourceToken>>> batches;
  int _cursor = 0;
  int fetchAllCount = 0;
  int invalidateAllCount = 0;
  final List<String> invalidated = <String>[];

  Map<ResourceKey, Result<ResourceToken>> get _current =>
      batches[_cursor.clamp(0, batches.length - 1)];

  @override
  Future<Result<ResourceToken>> tokenFor(ResourceKey key) async {
    final Result<ResourceToken>? result = _current[key];
    return result ??
        Failure<ResourceToken>(
          Problem(
            type: 'urn:diene:problem:resource-token',
            title: 'No token scripted',
            status: 401,
            data: <String, Object?>{'resource': key.mapKey},
          ),
        );
  }

  @override
  Future<Map<ResourceKey, Result<ResourceToken>>> fetchAllTokens(
    Iterable<ResourceKey> keys,
  ) async {
    fetchAllCount += 1;
    final Map<ResourceKey, Result<ResourceToken>> snapshot = _current;
    if (_cursor < batches.length - 1) {
      _cursor += 1;
    }
    return <ResourceKey, Result<ResourceToken>>{
      for (final ResourceKey key in keys)
        key: snapshot[key] ?? await tokenFor(key),
    };
  }

  @override
  void invalidate(ResourceKey key) => invalidated.add(key.mapKey);

  @override
  void invalidateAll() => invalidateAllCount += 1;
}

/// Scriptable [UserDirectory] fake.
final class FakeUserDirectory implements UserDirectory {
  FakeUserDirectory({
    this.getStatus = 200,
    this.postStatus = 201,
    this.throwOnGet = false,
  });

  int getStatus;
  int postStatus;
  bool throwOnGet;
  int getCount = 0;
  int postCount = 0;

  @override
  Future<int> getUserMe({
    required String backendId,
    required String accessToken,
  }) async {
    getCount += 1;
    if (throwOnGet) {
      throw StateError('directory transport failure');
    }
    return getStatus;
  }

  @override
  Future<int> postUser({
    required String backendId,
    required String accessToken,
    required String idToken,
  }) async {
    postCount += 1;
    return postStatus;
  }
}

/// Scriptable [AppHandoffApi] fake.
final class FakeAppHandoffApi implements AppHandoffApi {
  FakeAppHandoffApi({Result<RedeemResult>? result})
    : _result = result ?? Failure<RedeemResult>(appHandoffExpired());

  final Result<RedeemResult> _result;
  int redeemCount = 0;
  String? lastNonce;

  @override
  Future<Result<RedeemResult>> redeem({
    required String nonce,
    required DeviceInfo device,
  }) async {
    redeemCount += 1;
    lastNonce = nonce;
    return _result;
  }
}

/// Fake Doc B source returning a fixed doc (or throwing).
final class FakeLandscapeSelectorSource implements LandscapeSelectorSource {
  FakeLandscapeSelectorSource({this.doc, this.error});

  LandscapeSelectorDoc? doc;
  Object? error;
  int fetchCount = 0;

  @override
  Future<LandscapeSelectorDoc> fetch() async {
    fetchCount += 1;
    if (error != null) {
      throw error!;
    }
    return doc ?? (throw StateError('no landscape doc scripted'));
  }
}

/// Fake region pinger backed by a latency map keyed by landscape name; a `null`
/// entry (or a missing name) is unhealthy.
final class FakeRegionPinger implements RegionPinger {
  FakeRegionPinger(this.latencies);

  final Map<String, Duration?> latencies;
  final List<String> pinged = <String>[];

  @override
  Future<Duration?> ping(LandscapeEntry entry) async {
    pinged.add(entry.name);
    return latencies[entry.name];
  }
}

/// In-memory [HomeClaimStore].
final class MemoryHomeClaimStore implements HomeClaimStore {
  MemoryHomeClaimStore([this.value]);

  String? value;
  int reads = 0;
  int writes = 0;

  @override
  Future<String?> read() async {
    reads += 1;
    return value;
  }

  @override
  Future<void> write(String landscape) async {
    writes += 1;
    value = landscape;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

/// Fake Install Referrer source.
final class FakeInstallReferrerSource implements InstallReferrerSource {
  FakeInstallReferrerSource(this.referrer);

  String? referrer;
  bool processed = false;

  @override
  Future<String?> read() async => referrer;

  @override
  Future<void> markProcessed() async => processed = true;
}

/// Fake iOS clipboard carrier source.
final class FakeClipboardCarrierSource implements ClipboardCarrierSource {
  FakeClipboardCarrierSource(this.contents);

  String? contents;
  bool cleared = false;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> clearIfEquals(String value) async {
    if (contents?.trim() == value) {
      contents = null;
      cleared = true;
    }
  }
}
