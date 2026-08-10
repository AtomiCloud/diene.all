import 'dart:convert';
import 'dart:io';

import 'package:diene_e2e/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late StubServer server;
  late HttpClient client;

  setUp(() async {
    server = await StubServer.start();
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.close();
  });

  Future<HttpClientResponse> post(String path, String body) async {
    final HttpClientRequest req = await client.postUrl(
      Uri.parse('${server.baseUrl}$path'),
    );
    req.write(body);
    return req.close();
  }

  test('routes to a registered handler and records the request', () async {
    // Arrange.
    server.on(
      'POST',
      '/echo',
      (StubRequest r) => StubResponse.json(r.jsonBody()),
    );
    // Act.
    final HttpClientResponse resp = await post('/echo', '{"a":1}');
    final String out = await utf8.decoder.bind(resp).join();
    // Assert.
    expect(resp.statusCode, 200);
    expect(resp.headers.value('content-type'), contains('application/json'));
    expect(resp.headers.value('cache-control'), 'no-store');
    expect(jsonDecode(out), <String, Object?>{'a': 1});
    expect(server.requests, hasLength(1));
    expect(server.requests.single.path, '/echo');
    expect(server.requests.single.method, 'POST');
  });

  test('unregistered route returns 404', () async {
    final HttpClientResponse resp = await post('/nope', '');
    expect(resp.statusCode, 404);
    await resp.drain<void>();
  });

  test('jsonBody REJECTS a body that is not a JSON object', () async {
    // The assert-the-asserter half of the meta contract: a helper that decodes
    // untrusted input must be shown to FAIL on a known-bad case, not only to
    // pass on a good one. A JSON array and a bare scalar both decode fine but
    // are not objects, so both must throw rather than silently yield an empty
    // map — a stub that swallowed a malformed body would make a consumer's
    // negative-path test pass for the wrong reason.
    late Object? caught;
    server.on('POST', '/strict', (StubRequest r) {
      try {
        r.jsonBody();
        caught = null;
      } on FormatException catch (error) {
        caught = error;
      }
      return const StubResponse();
    });

    await (await post('/strict', '[1,2,3]')).drain<void>();
    expect(
      caught,
      isA<FormatException>(),
      reason: 'a JSON array is valid JSON but is not a JSON object',
    );

    await (await post('/strict', '"a string"')).drain<void>();
    expect(caught, isA<FormatException>(), reason: 'a scalar is not an object');

    // POSITIVE CONTROL: the same helper on a real object must NOT throw, or the
    // two cases above would prove nothing about discrimination.
    await (await post('/strict', '{"ok":true}')).drain<void>();
    expect(
      caught,
      isNull,
      reason: 'a JSON object must decode without throwing',
    );
  });

  test('clearRequests empties the log but keeps handlers', () async {
    server.on('POST', '/x', (StubRequest r) => const StubResponse());
    await (await post('/x', '')).drain<void>();
    expect(server.requests, hasLength(1));
    server.clearRequests();
    expect(server.requests, isEmpty);
    final HttpClientResponse resp = await post('/x', '');
    expect(resp.statusCode, 200);
    await resp.drain<void>();
  });
}
