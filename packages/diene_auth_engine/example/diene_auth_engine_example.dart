import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:diene_auth_engine/test_helper.dart';
import 'package:diene_result/diene_result.dart';

/// The engine-owned `authEngine` config block, as the `config` lib would hand
/// it over after merging YAML layers and `--dart-define` overrides. The OIDC
/// `issuer` is BAKED build-time config — it never arrives from an edge doc.
final AuthEngineConfig config = AuthEngineConfig.fromBlock(<String, Object?>{
  'issuer': 'https://api.lithium.lapras.cluster.atomi.cloud',
  'endpoint': 'https://logto.lithium.lapras.cluster.atomi.cloud',
  'appId': 'example-app',
  'redirectUri': 'https://app.lithium.lapras.cluster.atomi.cloud/callback',
  'scopes': <String>['openid', 'offline_access'],
});

/// The one backend this app talks to. `resourceName` occupies the M slot of the
/// LPSM coordinate, so the JWT `aud` is
/// `https://root.api.lithium.lapras.cluster.atomi.cloud`.
final ResourceKey apiResource = ResourceKey(
  platform: 'lithium',
  landscape: 'lapras',
  service: 'api',
  resourceName: 'root',
);

/// Redeems a store carrier into the `signIn(extraParams:)` payload. A missing
/// or expired carrier is not an error — it simply means "log in normally".
Future<Map<String, String>> deferredLoginParams(
  AppHandoffApi api,
  InstallReferrerSource referrer,
) async {
  final DeferredLoginClient client = DeferredLoginClient(
    api: api,
    device: const DeviceInfo(platform: 'android', appVersion: '1.0.0'),
    referrer: referrer,
  );
  final DeferredLoginOutcome outcome = await client.prepare();
  return switch (outcome) {
    DeferredLoginReady(:final Map<String, String> extraParams) => extraParams,
    DeferredLoginFallback() => const <String, String>{},
  };
}

Future<void> main() async {
  final DateTime now = DateTime.utc(2026, 7, 26);
  const String nonce = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

  // --- Deferred login: read the carrier, redeem it, get the extra params ----
  final FakeInstallReferrerSource referrer = FakeInstallReferrerSource(
    'utm_source=play&app_handoff=atomi-app-handoff%3Av1%3A$nonce',
  );
  final FakeAppHandoffApi handoff = FakeAppHandoffApi(
    result: const Ok<RedeemResult>(
      RedeemResult(token: 'one-time', email: 'user@example.com'),
    ),
  );
  final Map<String, String> extraParams = await deferredLoginParams(
    handoff,
    referrer,
  );
  assert(extraParams['one_time_token'] == 'one-time', 'carrier redeemed');
  assert(referrer.processed, 'the referrer is marked processed before redeem');

  // --- The IdP seam --------------------------------------------------------
  // A JWT carrying the exact `lithium_api = "true"` registration claim plus the
  // authoritative `home_landscape` claim.
  final String registered = AuthFixtures.registeredJwt(
    apiResource,
    extra: <String, Object?>{Claims.homeLandscape: 'lapras'},
  );
  final FakeAuthProvider provider = FakeAuthProvider(
    onSignIn: () => AuthFixtures.sessionTokens(now: now),
    resourceTokens: <String, ResourceToken>{
      apiResource.mapKey: AuthFixtures.resourceToken(
        now: now,
        jwtToken: registered,
      ),
    },
    idTokenValue: registered,
  );

  // --- Session lifecycle (C0 §12: 10-minute access, 14-day rotating refresh)
  final SessionController session = SessionController(
    provider: provider,
    now: () => now,
  );
  final SessionTokens tokens = AuthExpect.ok(
    await session.signIn(extraParams: extraParams),
  );
  assert(tokens.accessValidAt(now), 'the issued access token is live');
  assert(session.status == SessionStatus.authenticated, 'session is up');

  // --- Per-resource tokens through the IAuth seam --------------------------
  final IAuth auth = AuthCoordinator(provider: provider, now: () => now);
  final ResourceToken apiToken = AuthExpect.ok(
    await auth.tokenFor(apiResource),
  );
  assert(apiToken.token == registered, 'the resource token is cached per key');

  // --- Per-backend claims-first onboarding (C0 §8) -------------------------
  final BackendRegistry registry = BackendRegistry(<RegisteredBackend>[
    RegisteredBackend(
      backendId: 'lithium-api',
      resources: <ResourceKey>[apiResource],
      onboardingResource: apiResource,
    ),
  ]);
  final MultiBackendOnboarding onboarding = MultiBackendOnboarding(
    registry: registry,
    auth: auth,
    directory: FakeUserDirectory(),
    idToken: provider.idToken,
  );
  final Map<String, Result<OnboardingPhase>> phases = await onboarding.runAll();
  AuthExpect.phase(
    AuthExpect.ok(phases['lithium-api']!),
    OnboardingPhase.ready,
  );

  // --- Home landscape: the JWT claim decides, Doc B only when it is absent -
  final HomeClaimResolver homeResolver = HomeClaimResolver(
    claimReader: jwtHomeClaimReader(provider.idToken),
    selector: LandscapeSelectorClient(
      source: FakeLandscapeSelectorSource(
        doc: const LandscapeSelectorDoc(
          platform: 'lithium',
          tier: 'prod',
          landscapes: <LandscapeEntry>[
            LandscapeEntry(name: 'lapras', region: 'sgp'),
          ],
        ),
      ),
      pinger: FakeRegionPinger(<String, Duration?>{
        'lapras': const Duration(milliseconds: 12),
      }),
    ),
    store: MemoryHomeClaimStore(),
  );
  final HomeResolution home = AuthExpect.ok(await homeResolver.resolve());
  assert(home.landscape == 'lapras', 'the claim decided the home landscape');
  assert(home.kind == HomeResolutionKind.fromClaim, 'Doc B never ran');

  // --- returnTo: resume the exact protected route after login --------------
  final Uri target = Uri.parse('/orders/42?tab=history');
  final Uri redirect = AuthExpect.ok(
    ReturnTo.buildLoginRedirect(Uri.parse('/login'), target),
  );
  assert(
    redirect.queryParameters[ReturnTo.queryKey] == '/orders/42?tab=history',
    'path AND query survive the round trip',
  );
  final Uri resumed = ReturnTo.continueFrom(redirect, fallback: Uri.parse('/'));
  assert(resumed.toString() == target.toString(), 'resumed the exact route');

  // An absolute target is an open redirect and is refused, not followed.
  AuthExpect.errType(
    ReturnTo.capture(Uri.parse('https://evil.example/steal')),
    'urn:diene:problem:return-to',
  );

  // --- The whole flow in one call ------------------------------------------
  final SignInResult result = AuthExpect.ok(
    await SignInCoordinator(
      session: session,
      homeResolver: homeResolver,
      onboarding: onboarding,
    ).signIn(extraParams: extraParams, returnTo: target),
  );
  assert(result.home.landscape == 'lapras', 'routed to the claimed home');
  assert(result.continueTo == target, 'the deeplink target is preserved');
  assert(config.redeemPath == '/app-handoff/redeem', 'no doubled mount path');
}
