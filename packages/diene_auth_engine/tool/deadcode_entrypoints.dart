// Production dead-code root for the published `diene_auth_engine` surface.
//
// This is TOOLING, not a test. `dart_code_linter` otherwise treats only the
// public barrel (`diene_auth_engine.dart`) as an entrypoint and so reports every
// public member of `test_helper.dart` as unused. Referencing the public surface
// here keeps the production-only dead-code pass honest WITHOUT any exclusion
// list (R12 — two passes, no exclusions). `scripts/local/deadcode.sh` copies this
// file to `bin/main.dart` inside the production-only sandbox, so it must live in
// the member package where `package:diene_auth_engine` resolves, and it is kept
// out of the published archive by `.pubignore`.
//
// This file was LOST in the R-E19a transplant: the sample's copy was removed
// with the rest of `packages/diene_dart_lib/tool/` and no auth-engine equivalent
// was written, so `cp .../tool/deadcode_entrypoints.dart` failed and the
// "Production dead-code pass" step exited 1 in CI while the repository pass
// above it printed "no unused files found!".
import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:diene_auth_engine/test_helper.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

/// Touches the production surface, then the TestHelper surface, then proves the
/// helper failure type is reachable. Every reference is a real call so the
/// linter sees genuine use rather than a bare identifier mention.
Future<void> main() async {
  // A fixed instant: this tool is an analysis root, so it must be deterministic.
  final DateTime now = DateTime.utc(2026, 7, 27);

  // --- Production surface -------------------------------------------------
  final ResourceKey key = AuthFixtures.resourceKey();
  final SessionTokens tokens = AuthFixtures.sessionTokens(now: now);
  final ResourceToken token = AuthFixtures.resourceToken(
    now: now,
    jwtToken: AuthFixtures.jwt(<String, Object?>{'sub': 'u'}),
  );
  if (key.audience.scheme.isEmpty ||
      key.mapKey.isEmpty ||
      tokens.accessToken.isEmpty ||
      tokens.refreshToken.isEmpty ||
      tokens.refreshFamily.isEmpty ||
      token.token.isEmpty) {
    throw StateError('fixtures must build a usable identity');
  }

  // Token lifetimes and app-handoff constants (C0 §12 / §7).
  if (TokenLifetimes.access <= Duration.zero ||
      TokenLifetimes.refresh <= Duration.zero ||
      !TokenLifetimes.refreshRotating ||
      !TokenLifetimes.remintOnOpen ||
      AppHandoffConstants.nonceTtl <= Duration.zero ||
      AppHandoffConstants.oneTimeTokenExpiresInSeconds <= 0 ||
      AppHandoffConstants.defaultMount.isEmpty) {
    throw StateError('normative constants must be positive');
  }

  // Claims-first inspection (C0 §8 / §13).
  final Map<String, Object?> claims = Claims.decode(
    AuthFixtures.registeredJwt(key),
  );
  if (!Claims.hasRegistration(
    claims,
    platform: key.platform,
    service: key.service,
  )) {
    throw StateError('registered fixture must carry its claim');
  }
  Claims.home(Claims.decode(AuthFixtures.unregisteredJwt(key)));
  Claims.registrationKey(platform: key.platform, service: key.service);

  // App-handoff carrier parsing (C0 §7).
  final AppHandoffCarrier? carrier = AppHandoffCarrier.parseCanonical(
    'atomi-app-handoff:v1:${'A' * 43}',
  );
  if (carrier == null || carrier.canonicalText.isEmpty) {
    throw StateError('canonical carrier must parse');
  }
  AppHandoffCarrier.parseAndroidReferrer('utm_source=play');
  AppHandoffCarrier.parseClipboard(carrier.canonicalText);

  // Doc B selector (C0 §10) and the expiry problem envelope.
  LandscapeSelectorDoc.fromJson(<String, Object?>{
    'platform': 'lithium',
    'tier': 'prod',
    'landscapes': <Object?>[
      <String, Object?>{'name': 'raichu', 'region': 'sgp'},
    ],
  });
  final Problem expired = appHandoffExpired();

  // returnTo deeplink continuation — capture, build the login redirect, resolve
  // it back, and continue from the callback.
  final Result<String> captured = ReturnTo.capture(Uri.parse('/a?b=c'));
  AuthExpect.ok<String>(captured);
  final Uri login = Uri.parse('https://login.example/authorize');
  AuthExpect.ok<Uri>(ReturnTo.buildLoginRedirect(login, Uri.parse('/a?b=c')));
  AuthExpect.ok<Uri>(ReturnTo.resolve(captured.unwrap()));
  ReturnTo.continueFrom(
    login.replace(
      queryParameters: <String, String>{ReturnTo.queryKey: captured.unwrap()},
    ),
    fallback: Uri.parse('/'),
  );

  // --- TestHelper surface -------------------------------------------------
  const LandscapeEntry entry = LandscapeEntry(name: 'raichu', region: 'sgp');
  final FakeAuthProvider provider = FakeAuthProvider(onSignIn: () => tokens);
  final SessionController session = SessionController(provider: provider);
  final FakeAuth auth = FakeAuth(<Map<ResourceKey, Result<ResourceToken>>>[
    <ResourceKey, Result<ResourceToken>>{key: Ok<ResourceToken>(token)},
  ]);
  final FakeUserDirectory directory = FakeUserDirectory();
  final FakeAppHandoffApi handoff = FakeAppHandoffApi();
  final FakeInstallReferrerSource referrer = FakeInstallReferrerSource(null);
  final FakeClipboardCarrierSource clipboard = FakeClipboardCarrierSource(null);
  final FakeLandscapeSelectorSource docs = FakeLandscapeSelectorSource();
  final FakeRegionPinger pinger = FakeRegionPinger(<String, Duration>{
    entry.name: const Duration(milliseconds: 5),
  });
  final MemoryHomeClaimStore store = MemoryHomeClaimStore();

  await session.signIn();
  await auth.tokenFor(key);
  auth.invalidate(key);
  await directory.getUserMe(backendId: key.mapKey, accessToken: token.token);
  await directory.postUser(
    backendId: key.mapKey,
    accessToken: token.token,
    idToken: AuthFixtures.registeredJwt(key),
  );
  await handoff.redeem(
    nonce: 'n',
    device: const DeviceInfo(platform: 'ios'),
  );
  await referrer.read();
  await clipboard.read();
  await docs.fetch();
  await pinger.ping(entry);
  await store.write('raichu');
  await store.read();
  await store.clear();

  // Assertion helpers: accept a known-GOOD case on each arm...
  AuthExpect.ok<int>(const Ok<int>(1));
  AuthExpect.err<int>(Err<int>(expired));
  AuthExpect.errType<int>(Err<int>(expired), expired.type);
  AuthExpect.some<int>(const Some<int>(1));
  AuthExpect.none<int>(const None<int>());
  AuthExpect.phase(OnboardingPhase.ready, OnboardingPhase.ready);
  AuthExpect.status(expired, expired.status);

  // ...and prove the failure type is REACHABLE by rejecting a known-bad one. A
  // helper that can never fail is not an assertion.
  try {
    AuthExpect.ok<int>(Err<int>(expired));
    throw StateError('AuthExpect.ok must reject an Err');
  } on AuthAssertionError catch (error) {
    if (error.toString().isEmpty) {
      throw StateError('AuthAssertionError must describe itself');
    }
  }
}
