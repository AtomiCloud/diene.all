/// The remaining unit-ledger gaps: the OA3 `ResultSdk` error classification, the
/// `IoHttpTransport` socket-level error mapping, and `config.dart`'s value
/// equality plus its fail-closed parsers.
///
/// Every line here was uncovered because nothing in the inherited suite provoked
/// it — not because it is dead. Each is covered by asserting the behaviour.
library;

// `dart:io` also declares `HttpRequest`/`HttpResponse`, which would shadow this
// package's own transport types. Aliased so both are usable unambiguously.
import 'dart:io' as io;

import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _dio({
  Object? error,
  Response<Object?>? response,
  String? message,
  DioExceptionType type = DioExceptionType.unknown,
}) => DioException(
  requestOptions: RequestOptions(path: '/thing'),
  error: error,
  response: response,
  message: message,
  type: type,
);

Response<Object?> _response(int status, Object? data) => Response<Object?>(
  requestOptions: RequestOptions(path: '/thing'),
  statusCode: status,
  data: data,
);

void main() {
  group('ResultSdk classifies SDK failures', () {
    const ResultSdk sdk = ResultSdk();

    test('a successful invoke is Ok', () async {
      final Result<int> result = await sdk.call<int>(() async => 7);
      expect(result.isOk, isTrue);
      expect(result.unwrap(), 7);
    });

    test(
      'a DioException carrying a Problem surfaces THAT Problem losslessly',
      () async {
        // The backend adapter reports a token-resolution failure this way, so the
        // caller must get the auth Problem itself rather than a transport-shaped
        // substitute — losing it would hide WHY the call could not be made.
        final Problem authProblem = Problem(
          type: BridgeProblems.authTokenUnavailable,
          title: 'No token',
          status: 401,
          detail: 'platform/lapras/service/a',
        );

        final Result<int> result = await sdk.call<int>(
          () async => throw _dio(error: authProblem),
          endpoint: '/thing',
        );

        final Problem got = result.unwrapErr();
        expect(got.type, BridgeProblems.authTokenUnavailable);
        expect(got.status, 401);
        expect(got.detail, 'platform/lapras/service/a');
      },
    );

    test(
      'a DioException with a PROBLEM BODY classifies as that Problem',
      () async {
        final Result<int> result = await sdk.call<int>(
          () async => throw _dio(
            response: _response(404, <String, Object?>{
              'type': 'urn:example:missing',
              'title': 'Missing',
              'status': 404,
            }),
          ),
          endpoint: '/thing',
        );

        final Problem got = result.unwrapErr();
        expect(got.type, 'urn:example:missing');
        expect(got.status, 404);
      },
    );

    test(
      'a DioException with a NON-problem JSON body is unexpected-response',
      () async {
        final Result<int> result = await sdk.call<int>(
          () async => throw _dio(
            response: _response(400, <String, Object?>{'nope': 1}),
          ),
          endpoint: '/thing',
        );

        expect(result.unwrapErr().type, BridgeProblems.unexpectedResponse);
      },
    );

    test('a DioException with NO response is a transport failure', () async {
      // This is the `NetworkFailure(error.message ?? error.type.name)` branch.
      final Result<int> result = await sdk.call<int>(
        () async => throw _dio(message: 'connection refused'),
        endpoint: '/thing',
      );

      final Problem got = result.unwrapErr();
      expect(got.type, BridgeProblems.transportFailure);
      expect(got.data['reason'], contains('connection refused'));
    });

    test('a message-less DioException falls back to its TYPE name', () async {
      // Proves the `?? error.type.name` half of the same expression, which a
      // single message-carrying case would leave unexercised.
      final Result<int> result = await sdk.call<int>(
        () async => throw _dio(type: DioExceptionType.connectionTimeout),
        endpoint: '/thing',
      );

      expect(result.unwrapErr().data['reason'], contains('connectionTimeout'));
    });

    test('a NON-Dio throwable is wrapped as a 503 transport failure', () async {
      final Result<int> result = await sdk.call<int>(
        () async => throw ArgumentError('generator blew up'),
        endpoint: '/thing',
      );

      final Problem got = result.unwrapErr();
      expect(got.type, BridgeProblems.transportFailure);
      expect(got.status, 503);
      expect(got.detail, contains('generator blew up'));
      expect(got.data['endpoint'], '/thing');
    });

    test('with no endpoint the null-aware entry is omitted entirely', () async {
      // `'endpoint': ?endpoint` must DROP the key rather than store null.
      final Result<int> result = await sdk.call<int>(
        () async => throw StateError('boom'),
      );

      expect(result.unwrapErr().data.containsKey('endpoint'), isFalse);
    });
  });

  group('IoHttpTransport maps socket-level errors to NetworkFailure', () {
    test(
      'a connection to a closed port is a NetworkFailure, not a throw',
      () async {
        // Bind and immediately release a port so the connect is refused
        // deterministically, with no reliance on an external host.
        final io.ServerSocket probe = await io.ServerSocket.bind(
          io.InternetAddress.loopbackIPv4,
          0,
        );
        final int deadPort = probe.port;
        await probe.close();

        final IoHttpTransport transport = IoHttpTransport(
          timeout: const Duration(seconds: 2),
        );
        addTearDown(transport.close);

        final TransportOutcome outcome = await transport.send(
          HttpRequest(
            method: HttpMethod.get,
            url: Uri.parse('http://127.0.0.1:$deadPort/thing'),
          ),
        );

        // The contract is that a transport NEVER throws — a hard failure is data.
        expect(outcome, isA<NetworkFailure>());
        expect((outcome as NetworkFailure).reason, isNotEmpty);
      },
    );

    test('a request that outlives the timeout is a NetworkFailure', () async {
      // A server that accepts and then never responds exercises the timeout
      // branch without a real hung backend.
      final io.ServerSocket server = await io.ServerSocket.bind(
        io.InternetAddress.loopbackIPv4,
        0,
      );
      final List<io.Socket> held = <io.Socket>[];
      server.listen(held.add);
      addTearDown(() async {
        for (final io.Socket s in held) {
          s.destroy();
        }
        await server.close();
      });

      final IoHttpTransport transport = IoHttpTransport(
        timeout: const Duration(milliseconds: 250),
      );
      addTearDown(transport.close);

      final TransportOutcome outcome = await transport.send(
        HttpRequest(
          method: HttpMethod.get,
          url: Uri.parse('http://127.0.0.1:${server.port}/hang'),
        ),
      );

      expect(outcome, isA<NetworkFailure>());
    });

    test('a real 200 response is Received with its body', () async {
      final io.HttpServer server = await io.HttpServer.bind(
        io.InternetAddress.loopbackIPv4,
        0,
      );
      server.listen((io.HttpRequest req) async {
        req.response
          ..statusCode = 200
          ..headers.contentType = io.ContentType.json
          ..write('{"ok":true}');
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final IoHttpTransport transport = IoHttpTransport();
      addTearDown(transport.close);

      final TransportOutcome outcome = await transport.send(
        HttpRequest(
          method: HttpMethod.get,
          url: Uri.parse('http://127.0.0.1:${server.port}/ok'),
        ),
      );

      expect(outcome, isA<Received>());
      expect((outcome as Received).response.status, 200);
      expect(outcome.response.body, contains('"ok":true'));
    });
  });

  group('HttpRequest.withUrl', () {
    test('swaps the URL and preserves every other field', () {
      // This is what the rescue retry uses to re-target a request, so losing a
      // header or the body here would silently drop auth on a rescued call.
      final HttpRequest original = HttpRequest(
        method: HttpMethod.post,
        url: Uri.parse('https://primary.example.com/thing'),
        headers: <String, String>{'authorization': 'Bearer t'},
        body: '{"a":1}',
      );

      final HttpRequest moved = original.withUrl(
        Uri.parse('https://rescue.example.com/thing'),
      );

      expect(moved.url.host, 'rescue.example.com');
      expect(moved.method, HttpMethod.post);
      expect(moved.headers['authorization'], 'Bearer t');
      expect(moved.body, '{"a":1}');
    });
  });

  group('LpsmCoordinate value semantics', () {
    const LpsmCoordinate a = LpsmCoordinate(
      landscape: 'lapras',
      platform: 'platform',
      service: 'service',
      module: 'core',
    );
    const LpsmCoordinate sameValue = LpsmCoordinate(
      landscape: 'lapras',
      platform: 'platform',
      service: 'service',
      module: 'core',
    );
    const LpsmCoordinate different = LpsmCoordinate(
      landscape: 'lapras',
      platform: 'platform',
      service: 'service',
      module: 'other',
    );

    test('equal coordinates compare equal and hash alike', () {
      // The client tree and the rescue store key on this, so value equality is
      // load-bearing rather than cosmetic.
      //
      // CAUGHT BY THE ANALYZER, and it was a real weakness in my own test: the
      // first version put two IDENTICAL const literals in a set and asserted
      // length 1. `equal_elements_in_set` fired because Dart CANONICALISES
      // compile-time-identical consts into a single object — so that set would
      // have had one element even if `==` and `hashCode` were broken, and the
      // assertion proved nothing. `runtimeCopy` is built at RUNTIME from the
      // same field values, so it is a genuinely distinct instance and the set
      // collapsing to one entry is real evidence about `hashCode`/`==`.
      final LpsmCoordinate runtimeCopy = LpsmCoordinate(
        landscape: 'lap${'ras'}',
        platform: 'plat${'form'}',
        service: 'ser${'vice'}',
        module: 'co${'re'}',
      );

      expect(identical(a, runtimeCopy), isFalse, reason: 'distinct instances');
      expect(a, runtimeCopy);
      expect(a.hashCode, runtimeCopy.hashCode);
      expect(<LpsmCoordinate>{a, runtimeCopy}, hasLength(1));
      expect(a, sameValue);
    });

    test('a differing module is NOT equal', () {
      expect(a == different, isFalse);
      expect(a == Object(), isFalse);
    });

    test('toString is the dotted key', () {
      expect(a.toString(), 'lapras.platform.service.core');
      expect(a.toString(), a.key);
    });
  });

  group('config parsers fail closed', () {
    test('a non-list where a list is required throws FormatException', () {
      expect(
        () => ApiEngineConfig.fromMap(<String, Object?>{'backends': 'nope'}),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'an empty string where a value is required throws FormatException',
      () {
        expect(
          () => ApiEngineConfig.fromMap(<String, Object?>{
            'backends': <Object?>[
              <String, Object?>{
                'baseUrl': '',
                'lpsm': <String, Object?>{
                  'landscape': 'lapras',
                  'platform': 'platform',
                  'service': 'service',
                  'module': 'core',
                },
              },
            ],
          }),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test('a non-map where a map is required throws FormatException', () {
      expect(
        () => ApiEngineConfig.fromMap(<String, Object?>{
          'backends': <Object?>['not-a-map'],
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
