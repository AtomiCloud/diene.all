import 'dart:convert';
import 'dart:io';

import 'package:diene_e2e/diene_e2e.dart';
import 'package:diene_e2e/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

/// End-to-end meta test: the deferred-login journey driver against the shared
/// app-handoff fixture mounted on a stub server.
void main() {
  const String typeUri = 'https://svc/AppHandoffExpired';
  late StubServer server;
  late AppHandoffStub stub;
  late HttpClient client;
  late DateTime clock;

  setUp(() async {
    server = await StubServer.start();
    client = HttpClient();
    clock = DateTime.utc(2026, 7, 21, 12);
    stub = AppHandoffStub(problemTypeUri: typeUri)
      ..addUser(const AppHandoffUser(sub: 'u1', primaryEmail: 'a@b.com'))
      ..mintingUser = const AppHandoffUser(sub: 'u1', primaryEmail: 'a@b.com');
    stub.mount(server, now: () => clock);
  });

  tearDown(() async {
    client.close(force: true);
    await server.close();
  });

  // Mints a fresh nonce by POSTing to the stub's mint route.
  Future<String> mintNonce() async {
    final HttpClientRequest req = await client.postUrl(
      Uri.parse('${server.baseUrl}${stub.mountPath}'),
    );
    req.write('{}');
    final HttpClientResponse resp = await req.close();
    final String body = await utf8.decoder.bind(resp).join();
    final Map<String, Object?> json = (jsonDecode(body) as Map).map(
      (Object? k, Object? v) => MapEntry(k.toString(), v),
    );
    return AppHandoffMint.fromJson(json).nonce;
  }

  test('valid android carrier is redeemed into a token', () async {
    // Arrange.
    final String nonce = await mintNonce();
    final String carrier = buildAppHandoffInstallReferrer(nonce);
    final DeferredLoginJourney driver = DeferredLoginJourney(
      baseUrl: server.baseUrl,
      platform: 'android',
    );
    // Act.
    final DeferredLoginResult result = await driver.redeemCarrier(carrier);
    driver.close();
    // Assert.
    expect(result.outcome, DeferredLoginJourneyOutcome.redeemed);
    expect(result.redeem?.email, 'a@b.com');
    expect(result.redeem?.expiresIn, 120);
  });

  test('absent/invalid carrier falls back to interactive login', () async {
    final DeferredLoginJourney driver = DeferredLoginJourney(
      baseUrl: server.baseUrl,
      platform: 'ios',
    );
    final DeferredLoginResult result = await driver.redeemCarrier('garbage');
    driver.close();
    expect(result.outcome, DeferredLoginJourneyOutcome.interactiveFallback);
    expect(result.redeem, isNull);
  });

  test('expired nonce (410) falls back to interactive login', () async {
    // Arrange.
    final String nonce = await mintNonce();
    clock = clock.add(const Duration(minutes: 16));
    final DeferredLoginJourney driver = DeferredLoginJourney(
      baseUrl: server.baseUrl,
      platform: 'android',
    );
    // Act.
    final DeferredLoginResult result = await driver.redeemNonce(nonce);
    driver.close();
    // Assert.
    expect(result.outcome, DeferredLoginJourneyOutcome.interactiveFallback);
  });
}
