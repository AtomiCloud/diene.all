import 'dart:convert';
import 'dart:io';

import 'package:diene_e2e/diene_e2e.dart';
import 'package:diene_e2e/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

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
    final HttpClientRequest req = await client.postUrl(
      Uri.parse('${server.baseUrl}${stub.mountPath}'),
    );
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
    stub.mintingUser = const AppHandoffUser(sub: 'u1', primaryEmail: 'a@b.com');
    final (int mStatus, Map<String, Object?> mBody) = await mint();
    expect(mStatus, 200);
    final AppHandoffMint minted = AppHandoffMint.fromJson(mBody);
    // Act.
    final (int rStatus, Map<String, Object?> rBody) = await redeem(
      redeemBody(minted.nonce),
    );
    // Assert.
    expect(rStatus, 200);
    final AppHandoffRedeemResponse resp = AppHandoffRedeemResponse.fromJson(
      rBody,
    );
    expect(resp.email, 'a@b.com');
    expect(resp.expiresIn, 120);
  });

  test('single-use: replay returns the identical generic 410', () async {
    stub.mintingUser = const AppHandoffUser(sub: 'u1', primaryEmail: 'a@b.com');
    final AppHandoffMint minted = AppHandoffMint.fromJson((await mint()).$2);
    await redeem(redeemBody(minted.nonce)); // consume
    // Act: replay.
    final (int status, Map<String, Object?> body) = await redeem(
      redeemBody(minted.nonce),
    );
    // Assert.
    expect(status, 410);
    expect(body, stub.expiredBody);
  });

  test('every failure mode returns the exact same no-oracle body', () async {
    // Arrange: users for suspended / deleted / mismatch cases.
    stub
      ..addUser(
        const AppHandoffUser(
          sub: 'suspended',
          primaryEmail: 'a@b.com',
          isSuspended: true,
        ),
      )
      ..addUser(
        const AppHandoffUser(
          sub: 'deleted',
          primaryEmail: 'a@b.com',
          deleted: true,
        ),
      )
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
    stub.mintingUser = const AppHandoffUser(sub: 'u1', primaryEmail: 'a@b.com');
    final AppHandoffMint expiring = AppHandoffMint.fromJson((await mint()).$2);
    clock = clock.add(const Duration(minutes: 16));
    bodies.add((await redeem(redeemBody(expiring.nonce))).$2);

    // Assert: all identical to the canonical expired body — no distinguishing
    // detail leaks the real reason.
    for (final Map<String, Object?> body in bodies) {
      expect(body, stub.expiredBody);
    }
  });

  group('C0 v1 redeem input validation (with a valid active nonce)', () {
    late String nonce;

    setUp(() async {
      stub.mintingUser = const AppHandoffUser(
        sub: 'u1',
        primaryEmail: 'a@b.com',
      );
      nonce = AppHandoffMint.fromJson((await mint()).$2).nonce;
    });

    Future<int> statusOf(Object? body) async =>
        (await redeem(jsonEncode(body))).$1;

    test('minted nonce is exactly 32 bytes base64url (43 chars)', () {
      expect(isValidAppHandoffNonce(nonce), isTrue);
      expect(nonce.length, appHandoffNonceLength);
    });

    test('unknown top-level key -> 410 and nonce is NOT consumed', () async {
      // Arrange: valid active nonce + an extra top-level key.
      final (int status, Map<String, Object?> body) = await redeem(
        jsonEncode(<String, Object?>{
          'nonce': nonce,
          'device': <String, Object?>{'platform': 'android'},
          'campaign': 'x',
        }),
      );
      // Assert: rejected as invalid v1 input, indistinguishable body.
      expect(status, 410);
      expect(body, stub.expiredBody);
      // Validation happens before the claim, so the nonce still redeems.
      expect((await redeem(redeemBody(nonce))).$1, 200);
    });

    test('missing device -> 410', () async {
      expect(await statusOf(<String, Object?>{'nonce': nonce}), 410);
    });

    test('device not an object -> 410', () async {
      expect(
        await statusOf(<String, Object?>{'nonce': nonce, 'device': 'nope'}),
        410,
      );
    });

    test('missing device.platform -> 410', () async {
      expect(
        await statusOf(<String, Object?>{
          'nonce': nonce,
          'device': <String, Object?>{'model': 'x'},
        }),
        410,
      );
    });

    test('invalid device.platform value -> 410', () async {
      expect(
        await statusOf(<String, Object?>{
          'nonce': nonce,
          'device': <String, Object?>{'platform': 'windows'},
        }),
        410,
      );
    });

    test('unknown device key -> 410', () async {
      expect(
        await statusOf(<String, Object?>{
          'nonce': nonce,
          'device': <String, Object?>{'platform': 'ios', 'foo': 1},
        }),
        410,
      );
    });

    test('non-string nonce -> 410', () async {
      expect(
        await statusOf(<String, Object?>{
          'nonce': 123,
          'device': <String, Object?>{'platform': 'ios'},
        }),
        410,
      );
    });

    test('non-string optional device field -> 410', () async {
      expect(
        await statusOf(<String, Object?>{
          'nonce': nonce,
          'device': <String, Object?>{'platform': 'ios', 'appVersion': 5},
        }),
        410,
      );
    });

    test('valid optional device fields -> success', () async {
      expect(
        await statusOf(<String, Object?>{
          'nonce': nonce,
          'device': <String, Object?>{
            'platform': 'ios',
            'appVersion': '1.0.0',
            'osVersion': '17',
            'model': 'pixel',
          },
        }),
        200,
      );
    });
  });

  group('nonce TTL is the binding C0 15 minutes', () {
    test('valid just inside 15m; expired just after', () async {
      // Just inside the TTL.
      stub.mintingUser = const AppHandoffUser(
        sub: 'u1',
        primaryEmail: 'a@b.com',
      );
      final String a = AppHandoffMint.fromJson((await mint()).$2).nonce;
      clock = clock.add(const Duration(minutes: 14, seconds: 59));
      expect((await redeem(redeemBody(a))).$1, 200);

      // A fresh nonce driven just past the TTL.
      stub.mintingUser = const AppHandoffUser(
        sub: 'u1',
        primaryEmail: 'a@b.com',
      );
      final String b = AppHandoffMint.fromJson((await mint()).$2).nonce;
      clock = clock.add(const Duration(minutes: 15, seconds: 1));
      expect((await redeem(redeemBody(b))).$1, 410);
    });

    test('nonceTtl is fixed at 15 minutes (not overridable)', () {
      expect(AppHandoffStub.nonceTtl, const Duration(minutes: 15));
    });
  });
}

Map<String, Object?> _obj(String body) => (jsonDecode(body) as Map).map(
  (Object? k, Object? v) => MapEntry(k.toString(), v),
);
