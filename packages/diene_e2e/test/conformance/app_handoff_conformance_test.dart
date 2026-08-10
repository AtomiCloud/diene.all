import 'dart:convert';
import 'dart:io';

import 'package:diene_e2e/diene_e2e.dart';
import 'package:diene_e2e/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

/// Data-driven C0 §7 app-handoff conformance test.
///
/// Binds the implementation to the frozen, independently-ACCEPTED C0 R2
/// authoritative fixture (`test/fixtures/c0/identity.json`, byte-verifiable
/// SHA-256 recorded in `test/fixtures/c0/PROVENANCE.md`). This node consumes
/// ONLY the `identity` domain's §7 app-handoff case.
///
/// The FROZEN FIXTURE is the sole oracle in every assertion: routes, the
/// generic-expiry body, the accepted/rejected nonce alphabet, and the success
/// key set are all derived from the fixture (never from a hard-coded literal or
/// from the implementation getter under test), so a broadened or wrong
/// implementation fails here. A failure is a real contract defect — fix the
/// code, never the fixture.
void main() {
  // Load the vendored fixture at runtime and select the §7 case: the entry in
  // `.cases` carrying a `carrierPrefix` key.
  final Map<String, Object?> root = _obj(
    jsonDecode(File('test/fixtures/c0/identity.json').readAsStringSync()),
  );
  final Map<String, Object?> cases = _obj(root['cases']);
  final Map<String, Object?> c = cases.values
      .map(_obj)
      .firstWhere((Map<String, Object?> v) => v.containsKey('carrierPrefix'));

  // Fixture-derived route templates (`{mount}` is the placeholder for the
  // configured mount). Every mint/redeem HTTP call is driven from these.
  final Map<String, Object?> mintRoute = _obj(c['mintRoute']);
  final Map<String, Object?> redeemRoute = _obj(c['redeemRoute']);
  final String mintRouteTemplate = mintRoute['path']! as String;
  final String redeemRouteTemplate = redeemRoute['path']! as String;
  // The HTTP verb is driven from the fixture too, so a method change is
  // exercised through real input rather than only asserted against a literal.
  final String mintMethod = mintRoute['method']! as String;
  final String redeemMethod = redeemRoute['method']! as String;

  const String typeUri = 'https://svc/AppHandoffExpired';
  const AppHandoffUser primary = AppHandoffUser(
    sub: 'u1',
    primaryEmail: 'a@b.com',
  );

  late StubServer server;
  late HttpClient client;
  late AppHandoffStub stub;
  late DateTime clock;

  // Substitute the fixture route template's `{mount}` with the mount the stub
  // is actually mounted on, and resolve it against the running server.
  String routeUrl(String template) =>
      '${server.baseUrl}${template.replaceAll('{mount}', stub.mountPath)}';

  setUp(() async {
    server = await StubServer.start();
    client = HttpClient();
    clock = DateTime.utc(2026, 7, 21, 12);
    stub = AppHandoffStub(problemTypeUri: typeUri)..addUser(primary);
    stub.mount(server, now: () => clock);
  });

  tearDown(() async {
    client.close(force: true);
    await server.close();
  });

  Future<(int, Map<String, Object?>)> mint() async {
    final HttpClientRequest req = await client.openUrl(
      mintMethod,
      Uri.parse(routeUrl(mintRouteTemplate)),
    );
    req.write('{}');
    final HttpClientResponse resp = await req.close();
    final String body = await utf8.decoder.bind(resp).join();
    return (resp.statusCode, _obj(jsonDecode(body)));
  }

  Future<(int, Map<String, Object?>)> redeem(String rawBody) async {
    final HttpClientRequest req = await client.openUrl(
      redeemMethod,
      Uri.parse(routeUrl(redeemRouteTemplate)),
    );
    req.write(rawBody);
    final HttpClientResponse resp = await req.close();
    final String body = await utf8.decoder.bind(resp).join();
    return (resp.statusCode, _obj(jsonDecode(body)));
  }

  /// The generic 410 no-oracle body EXPECTED per the fixture: the injected
  /// problem-type URI plus `title`/`status`/`detail`/`data` read straight from
  /// `c['genericExpiryProblem']`. Built from the fixture, not from the impl.
  Map<String, Object?> fixtureExpiredBody() {
    final Map<String, Object?> problem = _obj(c['genericExpiryProblem']);
    return <String, Object?>{
      'type': typeUri,
      'title': problem['title'],
      'status': problem['status'],
      'detail': problem['detail'],
      'data': problem['data'],
    };
  }

  test('constants and routes match the frozen fixture', () {
    // Carrier prefix.
    expect(
      '$appHandoffCarrierScheme:$appHandoffCarrierVersion:',
      c['carrierPrefix'],
    );
    expect(appHandoffNonceLength, c['nonceLength']);

    // Routes: derive the package's full paths and compare DIRECTLY to the
    // fixture routes, with `{mount}` substituted consistently on both sides.
    expect(appHandoffDefaultMount, c['defaultMount']);
    expect(mintRoute['method'], 'POST');
    expect(redeemRoute['method'], 'POST');
    String subst(String template) =>
        template.replaceAll('{mount}', appHandoffDefaultMount);
    expect(appHandoffDefaultMount, subst(mintRouteTemplate));
    expect(
      '$appHandoffDefaultMount/$appHandoffRedeemPath',
      subst(redeemRouteTemplate),
    );

    // One-time token lifetime.
    expect(appHandoffTokenExpiresInSeconds, c['oneTimeTokenExpiresInSeconds']);

    // Generic no-oracle expiry problem — static constants tied to the fixture,
    // and the empty `data` map tied to the fixture's own `data`.
    final Map<String, Object?> problem = _obj(c['genericExpiryProblem']);
    expect(AppHandoffExpired.problemId, problem['id']);
    expect(AppHandoffExpired.status, problem['status']);
    expect(AppHandoffExpired.title, problem['title']);
    expect(AppHandoffExpired.detail, problem['detail']);
    expect(problem['data'], isEmpty);
    expect(AppHandoffExpired.withType('x').toJson()['data'], problem['data']);

    // Success response key set — exact equality to the fixture key set.
    expect(
      const AppHandoffRedeemResponse(
        token: 't',
        email: 'e',
      ).toJson().keys.toSet(),
      _stringSet(c['redeemSuccessKeys']),
    );
  });

  test('nonce codec accepts/rejects per the frozen fixture alphabet', () {
    final int nonceLength = c['nonceLength']! as int;
    final RegExp noncePattern = RegExp(c['noncePattern']! as String);
    final String prefix = c['carrierPrefix']! as String;
    final Map<String, Object?> carriers = _obj(c['carriers']);

    // ACCEPT: the canonical all-`A` sample plus every valid carrier nonce. Each
    // must satisfy the fixture regex AND the package predicate, at the
    // fixture-declared length.
    final List<String> accept = <String>[
      'A' * nonceLength,
      for (final Object? raw in _list(carriers['valid']))
        _obj(raw)['nonce']! as String,
    ];
    for (final String nonce in accept) {
      expect(nonce.length, nonceLength, reason: 'accept length: $nonce');
      expect(noncePattern.hasMatch(nonce), isTrue, reason: 'regex: $nonce');
      expect(isValidAppHandoffNonce(nonce), isTrue, reason: 'impl: $nonce');
    }

    // The padded-nonce invalid carrier's nonce portion (base64 padding `=`).
    final Map<String, Object?> paddedVector = _list(carriers['invalid'])
        .map(_obj)
        .firstWhere((Map<String, Object?> e) => e['name'] == 'padded-nonce');
    final String paddedNonce = (paddedVector['text']! as String).substring(
      prefix.length,
    );

    // REJECT: tripwires a broadened impl (padding, `+`, wrong length,
    // non-base64url chars) would wrongly accept. Each must be rejected by BOTH
    // the fixture regex and the package predicate.
    final List<String> reject = <String>[
      '${'A' * (nonceLength - 1)}=', // right length, base64 padding
      '${'A' * (nonceLength - 1)}+', // right length, non-base64url `+`
      'A' * (nonceLength - 1), // one char short
      'A' * (nonceLength + 1), // one char long
      paddedNonce, // the fixture padded-nonce vector's nonce
    ];
    for (final String nonce in reject) {
      expect(noncePattern.hasMatch(nonce), isFalse, reason: 'regex: $nonce');
      expect(isValidAppHandoffNonce(nonce), isFalse, reason: 'impl: $nonce');
    }
  });

  test('carriers parse per the frozen fixture', () {
    final Map<String, Object?> carriers = _obj(c['carriers']);

    for (final Object? raw in _list(carriers['valid'])) {
      final Map<String, Object?> entry = _obj(raw);
      final String expected = entry['nonce']! as String;
      if (entry.containsKey('text')) {
        expect(parseAppHandoffCarrier(entry['text']! as String), expected);
      }
      if (entry.containsKey('clipboard')) {
        expect(
          parseAppHandoffClipboard(entry['clipboard']! as String),
          expected,
        );
      }
      if (entry.containsKey('androidReferrer')) {
        expect(
          parseAppHandoffInstallReferrer(entry['androidReferrer']! as String),
          expected,
        );
      }
    }

    for (final Object? raw in _list(carriers['invalid'])) {
      final Map<String, Object?> entry = _obj(raw);
      if (entry.containsKey('text')) {
        expect(parseAppHandoffCarrier(entry['text']! as String), isNull);
      }
      if (entry.containsKey('androidReferrer')) {
        expect(
          parseAppHandoffInstallReferrer(entry['androidReferrer']! as String),
          isNull,
        );
      }
    }
  });

  test('valid redeem requests yield a token per the frozen fixture', () async {
    final Set<String> successKeys = _stringSet(c['redeemSuccessKeys']);
    final Object? expiresIn = c['oneTimeTokenExpiresInSeconds'];
    final Map<String, Object?> requests = _obj(c['redeemRequests']);

    for (final Object? raw in _list(requests['valid'])) {
      final Map<String, Object?> vector = _obj(raw);
      final String name = vector['name']?.toString() ?? '';
      // A fresh mint per vector so single-use never interferes.
      stub.mintingUser = primary;
      final String nonce = AppHandoffMint.fromJson((await mint()).$2).nonce;
      // Replace ONLY the nonce; preserve every other key of the raw body.
      final Map<String, Object?> body = <String, Object?>{
        ..._obj(vector['body']),
        'nonce': nonce,
      };

      final (int status, Map<String, Object?> resp) = await redeem(
        jsonEncode(body),
      );

      expect(status, 200, reason: name);
      // EXACT key set — an endpoint that adds keys must fail.
      expect(resp.keys.toSet(), successKeys, reason: name);
      expect(resp['expiresIn'], expiresIn, reason: name);
    }
  });

  test('invalid redeem requests return the fixture no-oracle body', () async {
    final Map<String, Object?> expected = fixtureExpiredBody();
    final Map<String, Object?> requests = _obj(c['redeemRequests']);

    for (final Object? raw in _list(requests['invalid'])) {
      final Map<String, Object?> vector = _obj(raw);
      final String name = vector['name']?.toString() ?? '';
      // A fresh active nonce per vector; only unknown-key rejection distinguishes
      // these from the valid vectors, so the nonce itself must be genuinely live.
      stub.mintingUser = primary;
      final String nonce = AppHandoffMint.fromJson((await mint()).$2).nonce;
      final Map<String, Object?> body = <String, Object?>{
        ..._obj(vector['body']),
        'nonce': nonce,
      };

      final (int status, Map<String, Object?> resp) = await redeem(
        jsonEncode(body),
      );

      // Compare the RAW response to the FIXTURE-derived body, not to a getter
      // built by the implementation under test.
      expect(status, 410, reason: name);
      expect(resp, expected, reason: name);
    }

    // Validate the implementation getter AGAINST the fixture (not trusted): the
    // no-oracle body it emits must equal the fixture-derived body.
    expect(stub.expiredBody, expected);
  });
}

Map<String, Object?> _obj(Object? value) =>
    (value! as Map).map((Object? k, Object? v) => MapEntry(k.toString(), v));

List<Object?> _list(Object? value) => (value! as List).cast<Object?>();

Set<String> _stringSet(Object? value) =>
    _list(value).map((Object? e) => e! as String).toSet();
