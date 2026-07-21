import 'dart:convert';
import 'dart:io';

import 'package:diene_e2e/diene_e2e.dart';
import 'package:diene_e2e/test_helper.dart';
import 'package:test/test.dart';

/// Fixture/behaviour-invariant meta tests for the shared app-handoff stub.
void main() {
  const String typeUri = 'https://svc/AppHandoffExpired';
  late StubServer server;
  late HttpClient client;
  late AppHandoffStub stub;
  late DateTime clock;

  setUp(() async {
    server = await StubServer.start();
    client = HttpClient();
    clock = DateTime.utc(2026, 7, 21, 12);
    stub = AppHandoffStub(problemTypeUri: typeUri)
      ..addUser(const AppHandoffUser(sub: 'u1', primaryEmail: 'a@b.com'));
    stub.mount(server, now: () => clock);
  });

  tearDown(() async {
    client.close(force: true);
    await server.close();
  });

  Future<(int, Map<String, Object?>)> mint() async {
    final HttpClientRequest req =
        await client.postUrl(Uri.parse('${server.baseUrl}${stub.mountPath}'));
    req.write('{}');
    final HttpClientResponse resp = await req.close();
    final String body = await utf8.decoder.bind(resp).join();
    return (resp.statusCode, _obj(body));
  }

  Future<(int, Map<String, Object?>)> redeem(String rawBody) async {
    final HttpClientRequest req = await client.postUrl(
      Uri.parse('${server.baseUrl}${stub.mountPath}/$appHandoffRedeemPath'),
    );
    req.write(rawBody);
    final HttpClientResponse resp = await req.close();
    final String body = await utf8.decoder.bind(resp).join();
    return (resp.statusCode, _obj(body));
  }

  String redeemBody(String nonce) => jsonEncode(
        AppHandoffRedeemRequest(
          nonce: nonce,
          device: const AppHandoffDevice(platform: 'android'),
        ).toJson(),
      );

  test('happy path: mint then redeem yields a token, expiresIn 120', () async {
    // Arrange.
    stub.mintingUser =
        const AppHandoffUser(sub: 'u1', primaryEmail: 'a@b.com');
    final (int mStatus, Map<String, Object?> mBody) = await mint();
    expect(mStatus, 200);
    final AppHandoffMint minted = AppHandoffMint.fromJson(mBody);
    // Act.
    final (int rStatus, Map<String, Object?> rBody) =
        await redeem(redeemBody(minted.nonce));
    // Assert.
    expect(rStatus, 200);
    final AppHandoffRedeemResponse resp =
        AppHandoffRedeemResponse.fromJson(rBody);
    expect(resp.email, 'a@b.com');
    expect(resp.expiresIn, 120);
  });

  test('single-use: replay returns the identical generic 410', () async {
    stub.mintingUser =
        const AppHandoffUser(sub: 'u1', primaryEmail: 'a@b.com');
    final AppHandoffMint minted =
        AppHandoffMint.fromJson((await mint()).$2);
    await redeem(redeemBody(minted.nonce)); // consume
    // Act: replay.
    final (int status, Map<String, Object?> body) =
        await redeem(redeemBody(minted.nonce));
    // Assert.
    expect(status, 410);
    expect(body, stub.expiredBody);
  });

  test('every failure mode returns the exact same no-oracle body', () async {
    // Arrange: users for suspended / deleted / mismatch cases.
    stub
      ..addUser(const AppHandoffUser(
          sub: 'suspended', primaryEmail: 'a@b.com', isSuspended: true))
      ..addUser(const AppHandoffUser(
          sub: 'deleted', primaryEmail: 'a@b.com', deleted: true))
      ..addUser(const AppHandoffUser(sub: 'rebound', primaryEmail: 'z@z.com'));

    final List<Map<String, Object?>> bodies = <Map<String, Object?>>[];

    // Unknown nonce.
    bodies.add((await redeem(redeemBody('A' * appHandoffNonceLength))).$2);
    // Malformed JSON.
    bodies.add((await redeem('not json')).$2);
    // Missing nonce key.
    bodies.add((await redeem('{"device":{"platform":"ios"}}')).$2);

    // Suspended / deleted / email-rebound each need a fresh mint.
    for (final String sub in <String>['suspended', 'deleted', 'rebound']) {
      stub.mintingUser = AppHandoffUser(sub: sub, primaryEmail: 'a@b.com');
      final AppHandoffMint m = AppHandoffMint.fromJson((await mint()).$2);
      bodies.add((await redeem(redeemBody(m.nonce))).$2);
    }

    // Expired nonce (advance the clock past the 15-min TTL).
    stub.mintingUser =
        const AppHandoffUser(sub: 'u1', primaryEmail: 'a@b.com');
    final AppHandoffMint expiring = AppHandoffMint.fromJson((await mint()).$2);
    clock = clock.add(const Duration(minutes: 16));
    bodies.add((await redeem(redeemBody(expiring.nonce))).$2);

    // Assert: all identical to the canonical expired body — no distinguishing
    // detail leaks the real reason.
    for (final Map<String, Object?> body in bodies) {
      expect(body, stub.expiredBody);
    }
  });
}

Map<String, Object?> _obj(String body) => (jsonDecode(body) as Map)
    .map((Object? k, Object? v) => MapEntry(k.toString(), v));
