import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:diene_auth_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logto_dart_sdk/logto_dart_sdk.dart';

// Adapter-level regressions for the LogtoAuthProvider TOKEN seams, driven through
// an injected LogtoClient stand-in so nothing here touches a live IdP, secure
// storage, or a web-auth window.
//
// The documented PARITY DELTA is the subject: Logto's SDK owns refresh rotation
// internally and never surfaces a refresh token, so this adapter SYNTHESIZES the
// family bookkeeping. These tests pin that synthesis — the family carries across
// a refresh, the rotation counter advances, and reMintOnOpen replaces ONLY the
// access half while preserving the caller's refresh state.
void main() {
  final AuthEngineConfig config = AuthEngineConfig.fromBlock(<String, Object?>{
    'issuer': 'https://api.lithium.platform.mew.cluster.atomi.cloud',
    'endpoint': 'https://logto.example.com',
    'appId': 'mobile',
    'redirectUri': 'cloud.atomi.app://callback',
    'scopes': <String>['openid', 'offline_access', 'profile'],
  });
  final ResourceKey primary = AuthFixtures.resourceKey();
  final ResourceKey secondary = AuthFixtures.resourceKey(service: 'billing');
  final DateTime now = DateTime.utc(2026, 7, 21, 9);
  final DateTime accessExpiry = now.add(const Duration(minutes: 10));

  LogtoAuthProvider providerWith(
    _StubLogtoClient client, {
    Future<String?> Function()? claimTokenRefresher,
  }) => LogtoAuthProvider(
    config: config,
    primaryResource: primary,
    resources: <ResourceKey>[secondary],
    client: client,
    now: () => now,
    claimTokenRefresher: claimTokenRefresher,
  );

  _StubLogtoClient stubClient(Map<String, String> tokensByAudience) =>
      _StubLogtoClient(
        config: LogtoConfig(
          endpoint: config.endpoint.toString(),
          appId: config.appId,
        ),
        tokensByAudience: tokensByAudience,
        expiresAt: accessExpiry,
      );

  group('signIn', () {
    test('splits login_hint out of extraParams and mints a session', () async {
      // Arrange — `login_hint` is a FIRST-CLASS SDK parameter, not an extra, so
      // it must be lifted out rather than forwarded in the extras bag.
      final _StubLogtoClient client = stubClient(<String, String>{
        primary.audience.toString(): 'primary-access',
      });
      final LogtoAuthProvider provider = providerWith(client);

      // Act
      final SessionTokens tokens = await provider.signIn(
        extraParams: <String, String>{
          'login_hint': 'trainer@atomi.cloud',
          'one_time_token': 'handoff-token',
        },
      );

      // Assert
      expect(client.signInRedirectUri, config.redirectUri.toString());
      expect(client.signInLoginHint, 'trainer@atomi.cloud');
      expect(client.signInExtraParams, <String, String>{
        'one_time_token': 'handoff-token',
      });
      expect(tokens.accessToken, 'primary-access');
      expect(tokens.accessExpiresAt, accessExpiry);
      // The SDK owns rotation, so the family is a synthesized marker.
      expect(tokens.refreshFamily, 'logto-sdk');
      expect(tokens.refreshToken, 'logto-refresh-1');
      expect(tokens.refreshExpiresAt, now.add(TokenLifetimes.refresh));
    });

    test('passes null extras when only a login_hint was supplied', () async {
      // Arrange — an EMPTY extras map must become null, not `{}`, so the SDK
      // does not append an empty query fragment.
      final _StubLogtoClient client = stubClient(<String, String>{
        primary.audience.toString(): 'primary-access',
      });
      final LogtoAuthProvider provider = providerWith(client);

      // Act
      await provider.signIn(
        extraParams: <String, String>{'login_hint': 'trainer@atomi.cloud'},
      );

      // Assert
      expect(client.signInExtraParams, isNull);
      expect(client.signInLoginHint, 'trainer@atomi.cloud');
    });

    test('passes no login_hint when none was supplied', () async {
      // Arrange
      final _StubLogtoClient client = stubClient(<String, String>{
        primary.audience.toString(): 'primary-access',
      });
      final LogtoAuthProvider provider = providerWith(client);

      // Act
      await provider.signIn();

      // Assert
      expect(client.signInLoginHint, isNull);
      expect(client.signInExtraParams, isNull);
    });
  });

  group('refresh', () {
    test('carries the caller family across and advances the rotation', () async {
      // Arrange
      final _StubLogtoClient client = stubClient(<String, String>{
        primary.audience.toString(): 'rotated-access',
      });
      final LogtoAuthProvider provider = providerWith(client);
      final SessionTokens current = AuthFixtures.sessionTokens(
        now: now,
        refreshFamily: 'family-7',
      );

      // Act — two refreshes off the same family.
      final SessionTokens first = await provider.refresh(current);
      final SessionTokens second = await provider.refresh(first);

      // Assert — the family is PRESERVED (a changed family is the theft signal
      // SessionController acts on), while the synthesized token advances.
      expect(first.refreshFamily, 'family-7');
      expect(second.refreshFamily, 'family-7');
      expect(first.refreshToken, 'logto-refresh-1');
      expect(second.refreshToken, 'logto-refresh-2');
      expect(second.accessToken, 'rotated-access');
    });
  });

  group('reMintOnOpen', () {
    test('replaces only the access half and preserves refresh state', () async {
      // Arrange
      final _StubLogtoClient client = stubClient(<String, String>{
        primary.audience.toString(): 'reminted-access',
      });
      final LogtoAuthProvider provider = providerWith(client);
      final SessionTokens current = AuthFixtures.sessionTokens(
        now: now,
        accessToken: 'stale-access',
        refreshToken: 'refresh-abc',
        refreshFamily: 'family-7',
      );

      // Act
      final SessionTokens reminted = await provider.reMintOnOpen(current);

      // Assert — cold-open re-mint touches the ACCESS half only.
      expect(reminted.accessToken, 'reminted-access');
      expect(reminted.accessExpiresAt, accessExpiry);
      expect(reminted.refreshToken, 'refresh-abc');
      expect(reminted.refreshFamily, 'family-7');
      expect(reminted.refreshExpiresAt, current.refreshExpiresAt);
    });
  });

  group('resourceToken', () {
    test(
      'resolves a NON-primary resource through the same access seam',
      () async {
        // Arrange — the audience is what the SDK is asked for, per C0 §8.
        final _StubLogtoClient client = stubClient(<String, String>{
          primary.audience.toString(): 'primary-access',
          secondary.audience.toString(): 'billing-access',
        });
        final LogtoAuthProvider provider = providerWith(client);

        // Act
        final ResourceToken token = await provider.resourceToken(secondary);

        // Assert
        expect(token.token, 'billing-access');
        expect(token.expiresAt, accessExpiry);
        expect(client.requestedResources, <String>[
          secondary.audience.toString(),
        ]);
      },
    );

    test(
      'throws a StateError naming the map key when Logto returns no token',
      () async {
        // Arrange — nothing scripted for the requested audience.
        final _StubLogtoClient client = stubClient(const <String, String>{});
        final LogtoAuthProvider provider = providerWith(client);

        // Act + Assert — fail LOUDLY rather than fabricate an empty token.
        await expectLater(
          provider.resourceToken(primary),
          throwsA(
            isA<StateError>().having(
              (StateError e) => e.message,
              'message',
              contains(primary.mapKey),
            ),
          ),
        );
      },
    );

    test('normalizes a non-UTC expiry to UTC', () async {
      // Arrange — the SDK hands back whatever zone the wire carried; every
      // family comparison is UTC, so the adapter must normalize.
      final DateTime localExpiry = DateTime.parse('2026-07-21T09:10:00+08:00');
      final _StubLogtoClient client = _StubLogtoClient(
        config: LogtoConfig(
          endpoint: config.endpoint.toString(),
          appId: config.appId,
        ),
        tokensByAudience: <String, String>{
          primary.audience.toString(): 'primary-access',
        },
        expiresAt: localExpiry,
      );
      final LogtoAuthProvider provider = providerWith(client);

      // Act
      final ResourceToken token = await provider.resourceToken(primary);

      // Assert
      expect(token.expiresAt.isUtc, isTrue);
      expect(token.expiresAt, localExpiry.toUtc());
    });
  });

  group('idToken / signOut', () {
    test('reads the id token straight off the SDK', () async {
      // Arrange
      final _StubLogtoClient client = stubClient(const <String, String>{})
        ..idTokenValue = 'header.id-payload.sig';
      final LogtoAuthProvider provider = providerWith(client);

      // Act + Assert
      expect(await provider.idToken(), 'header.id-payload.sig');
    });

    test('signs out against the configured redirect URI', () async {
      // Arrange
      final _StubLogtoClient client = stubClient(const <String, String>{});
      final LogtoAuthProvider provider = providerWith(client);

      // Act
      await provider.signOut();

      // Assert
      expect(client.signOutRedirectUri, config.redirectUri.toString());
    });
  });

  group('freshClaimToken', () {
    test('returns the exact refresher token, never a cached read', () async {
      // Arrange — the SDK cannot force-refresh a still-valid token, so the
      // guaranteed-fresh claim token comes ONLY from the injected seam.
      final _StubLogtoClient client = stubClient(<String, String>{
        primary.audience.toString(): 'stale-cached-access',
      });
      final LogtoAuthProvider provider = providerWith(
        client,
        claimTokenRefresher: () async => 'header.fresh-claims.sig',
      );

      // Act + Assert
      expect(await provider.freshClaimToken(), 'header.fresh-claims.sig');
    });
  });
}

/// Stand-in for [LogtoClient] that records what the adapter asked for and hands
/// back scripted tokens. Subclassing (rather than reimplementing) keeps the real
/// SDK signatures authoritative: a breaking SDK change fails to compile here.
///
/// Every method the adapter touches is overridden, so the inherited secure
/// storage / web-auth paths are never entered.
final class _StubLogtoClient extends LogtoClient {
  _StubLogtoClient({
    required super.config,
    required this.tokensByAudience,
    required this._expiresAt,
  });

  final Map<String, String> tokensByAudience;
  final DateTime _expiresAt;

  String? idTokenValue;
  String? signInRedirectUri;
  String? signInLoginHint;
  Map<String, String>? signInExtraParams;
  String? signOutRedirectUri;
  final List<String> requestedResources = <String>[];

  @override
  Future<String?> get idToken async => idTokenValue;

  @override
  Future<AccessToken?> getAccessToken({
    String? resource,
    String? organizationId,
  }) async {
    requestedResources.add(resource ?? '');
    final String? token = tokensByAudience[resource];
    if (token == null) {
      return null;
    }
    return AccessToken(
      token: token,
      scope: 'openid offline_access',
      expiresAt: _expiresAt,
    );
  }

  @override
  Future<void> signIn(
    String redirectUri, {
    InteractionMode? interactionMode,
    String? loginHint,
    String? directSignIn,
    FirstScreen? firstScreen,
    List<IdentifierType>? identifiers,
    Map<String, String>? extraParams,
  }) async {
    signInRedirectUri = redirectUri;
    signInLoginHint = loginHint;
    signInExtraParams = extraParams;
  }

  @override
  Future<void> signOut(String redirectUri) async =>
      signOutRedirectUri = redirectUri;
}
