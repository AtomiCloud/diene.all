// Drive the C0 §7 deferred-login (app-handoff) journey end to end against the
// shared stub, then assert the outcome — the whole reason this package exists.
//
// TWO IMPORTS, and the split is the point. `diene_e2e.dart` is the VERSION TRAIN:
// depending on this one package gives you the coherent runtime API of all seven
// L-dart members, so a consumer pins one version instead of seven.
// `test_helper.dart` is the TEST HARNESS: the stub server, the journey drivers,
// the shared app-handoff fixture, plain-throw assertions, and every member's own
// test helper re-exported. Importing the harness never drags a test framework
// into a production dependency graph — everything in it is fakes, builders and
// plain-throw assertions.
//
// `print` is the right output for a runnable example, so the production-code lint
// is waived for this file only.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:diene_e2e/diene_e2e.dart';
import 'package:diene_e2e/test_helper.dart';

Future<void> main() async {
  // 1. Stand up the shared app-handoff stub. There is exactly ONE stub server in
  //    the family and it is defined WITH the C0 contract — this package consumes
  //    it rather than building a second one, so a consumer's journey is tested
  //    against the same behaviour the contract specifies.
  final StubServer server = await StubServer.start();
  final AppHandoffStub handoff = AppHandoffStub(
    problemTypeUri: 'https://api.example.com/AppHandoffExpired',
  )..addUser(const AppHandoffUser(sub: 'user-1', primaryEmail: 'a@b.com'));
  handoff.mount(server);

  // 2. Mint a carrier the way the store install flow would. `mintingUser` is set
  //    explicitly because the real server reads that identity from the
  //    authenticated session; the stub refuses to mint without it rather than
  //    attributing a token to nobody.
  handoff.mintingUser = const AppHandoffUser(
    sub: 'user-1',
    primaryEmail: 'a@b.com',
  );

  // 3. Drive the mobile client's half of the flow: parse the carrier, redeem the
  //    nonce, fall back to interactive login on any failure.
  final DeferredLoginJourney journey = DeferredLoginJourney(
    baseUrl: server.baseUrl,
    platform: 'android',
  );

  // The carrier is BUILT with the package's own codec rather than hand-written.
  // A hand-written referrer string is how you get a silent interactive-fallback
  // that looks like a passing journey: `parseAppHandoffInstallReferrer` requires
  // exactly one correctly-named `app_handoff` field, so a near-miss parses to
  // null and the redeem never happens.
  // Minted over REAL HTTP against the mounted route, the same call the backend
  // would receive, so the example exercises the path a consumer's journey takes.
  final HttpClient client = HttpClient();
  final HttpClientRequest mintRequest = await client.postUrl(
    Uri.parse('${server.baseUrl}${handoff.mountPath}'),
  );
  mintRequest.write('{}');
  final HttpClientResponse mintResponse = await mintRequest.close();
  final String mintBody = await utf8.decoder.bind(mintResponse).join();
  final String nonce = AppHandoffMint.fromJson(
    (jsonDecode(mintBody) as Map<Object?, Object?>).map(
      (Object? k, Object? v) => MapEntry<String, Object?>(k.toString(), v),
    ),
  ).nonce;

  final String referrer = buildAppHandoffInstallReferrer(
    nonce,
    extraFields: <String, String>{
      'utm_source': 'play',
      'utm_campaign': 'launch',
    },
  );

  final Journey flow = Journey('deferred login', <JourneyStep>[
    JourneyStep('carrier redeems into a one-time token', () async {
      final DeferredLoginResult result = await journey.redeemCarrier(referrer);
      // Assert the SPECIFIC branch. Accepting either outcome would make this
      // step unfalsifiable — an interactive fallback caused by a broken carrier
      // would read as success.
      return result.outcome == DeferredLoginJourneyOutcome.redeemed &&
          result.redeem != null;
    }),
    JourneyStep('a replayed nonce is refused', () async {
      // Single-use is a contract property, so the second redeem of the same
      // nonce must fall back rather than mint again.
      final DeferredLoginResult replay = await journey.redeemNonce(nonce);
      return replay.outcome == DeferredLoginJourneyOutcome.interactiveFallback;
    }),
  ]);

  final JourneyResult outcome = await flow.run();

  // 4. Assert with the harness's plain-throw helpers. They throw
  //    JourneyAssertionError rather than depending on `package:test`, so they
  //    work inside whatever runner the consumer already has.
  expectJourneyOk(outcome);
  expectTrue(server.requests.isNotEmpty, 'the journey must reach the server');
  print(
    'journey ${flow.name}: ${outcome.steps.length} steps, ok=${outcome.ok}',
  );

  // 5. The version train in one line: `Problem` comes from diene_problems and
  //    `Result` from diene_result, both reached through this single package.
  //    Every fallible member API returns a Result and never throws.
  const Result<int> resolved = Ok<int>(1);
  print('bundled Result resolves to ${expectOk(resolved)}');

  client.close(force: true);
  await server.close();
  journey.close();
}
