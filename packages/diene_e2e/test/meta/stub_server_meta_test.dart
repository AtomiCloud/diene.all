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
