import 'dart:convert';
import 'dart:io' as io;

import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _id(Map<String, Object?> json) => json;

/// Send a GET to [url] through [transport] and fold it into a Result.
Future<Result<Map<String, Object?>>> _get(
  HttpTransport transport,
  Uri url,
) async {
  final TransportOutcome outcome = await transport.send(
    HttpRequest(method: HttpMethod.get, url: url),
  );
  return toResult<Map<String, Object?>>(
    outcome,
    decode: _id,
    endpoint: url.path,
  );
}

/// META TIER — contract parity. The SAME behavioural suite runs against a real
/// dart:io HTTP transport AND the [FakeHttpTransport], proving the fake honours
/// the real reconciliation contract (int-grade by nature).
void main() {
  late io.HttpServer server;
  late Uri base;
  late int deadPort;

  setUpAll(() async {
    server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((io.HttpRequest request) async {
      switch (request.uri.path) {
        case '/ok':
          request.response
            ..statusCode = 200
            ..headers.contentType = io.ContentType.json
            ..write(jsonEncode(<String, Object?>{'ok': true}));
        case '/problem':
          request.response
            ..statusCode = 409
            ..headers.contentType = io.ContentType.json
            ..write(
              jsonEncode(
                Problem(
                  type: 'urn:diene:problem:conflict',
                  title: 'Conflict',
                  status: 409,
                ).toJson(),
              ),
            );
        default:
          request.response
            ..statusCode = 502
            ..write('Bad Gateway');
      }
      await request.response.close();
    });

    // A guaranteed-closed port for the network-failure case.
    final io.ServerSocket probe = await io.ServerSocket.bind(
      io.InternetAddress.loopbackIPv4,
      0,
    );
    deadPort = probe.port;
    await probe.close();
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  /// The shared contract: (transport, urlFor, deadUrl) → assertions.
  void contractSuite(
    String label,
    HttpTransport Function() build,
    Uri Function(String path) urlFor,
    Uri Function() deadUrl,
  ) {
    group(label, () {
      test('200 JSON → Ok', () async {
        expect(expectOk(await _get(build(), urlFor('/ok')))['ok'], true);
      });
      test('409 problem body → that Problem', () async {
        expectProblemType(
          await _get(build(), urlFor('/problem')),
          'urn:diene:problem:conflict',
        );
      });
      test('non-JSON error → transport-failure', () async {
        expectProblemType(
          await _get(build(), urlFor('/other')),
          BridgeProblems.transportFailure,
        );
      });
      test('network failure → transport-failure', () async {
        expectProblemType(
          await _get(build(), deadUrl()),
          BridgeProblems.transportFailure,
        );
      });
    });
  }

  // Real dart:io transport against the loopback server.
  contractSuite(
    'real IoHttpTransport',
    IoHttpTransport.new,
    (String path) => base.replace(path: path),
    () => Uri.parse('http://127.0.0.1:$deadPort/ok'),
  );

  // Fake transport scripted with the SAME outcomes.
  contractSuite(
    'FakeHttpTransport parity',
    () => FakeHttpTransport(
      (HttpRequest request) => switch (request.url.path) {
        '/ok' => okJson(<String, Object?>{'ok': true}),
        '/problem' => problemResponse(
          Problem(
            type: 'urn:diene:problem:conflict',
            title: 'Conflict',
            status: 409,
          ),
        ),
        '/dead' => networkFailure('refused'),
        _ => nonJsonResponse(status: 502),
      },
    ),
    (String path) => Uri.parse('http://fake.test$path'),
    () => Uri.parse('http://fake.test/dead'),
  );
}
