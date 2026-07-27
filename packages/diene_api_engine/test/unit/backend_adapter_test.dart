/// `BackendClientAdapter` — the dio `HttpClientAdapter` that drives a generated
/// SDK through a `Backend`'s production pipeline.
///
/// This was the last large block in the unit ledger. It is only reachable by
/// actually issuing a request through a `Dio` instance configured with the
/// adapter, which is exactly how a generated retrofit client uses it — so these
/// tests drive it the way the real SDK does rather than calling internals.
library;

import 'dart:convert';

import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

LpsmCoordinate _coord(String module) => LpsmCoordinate(
  landscape: 'lapras',
  platform: 'platform',
  service: 'service',
  module: module,
);

RescueConfig _disabledRescue() => RescueConfig(
  enabled: false,
  issuer: Uri.parse('https://unused.example'),
  catalogHosts: const <String>[],
  endpointSuffixAllowlist: const <String>[],
);

/// An engine whose single backend is served by [transport].
ApiEngine _engine(HttpTransport transport, {IAuth? auth, String? resource}) =>
    ApiEngine.fromConfig(
      ApiEngineConfig(
        backends: <BackendConfig>[
          BackendConfig(
            coordinate: _coord('a'),
            baseUrl: Uri.parse('https://primary.example.com'),
            resourceName: resource,
          ),
        ],
        rescue: _disabledRescue(),
      ),
      auth: auth,
      transport: transport,
    );

/// A `Dio` wired through the adapter, as a generated SDK would be.
Dio _dio(ApiEngine engine) {
  final Backend backend = engine.backend(_coord('a'))!;
  return Dio(BaseOptions(baseUrl: backend.config.baseUrl.toString()))
    ..httpClientAdapter = BackendClientAdapter(backend);
}

void main() {
  group('BackendClientAdapter drives the production pipeline', () {
    test('a received response is returned to dio with status and body', () async {
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest _) => okJson(<String, Object?>{'who': 'a'}),
      );

      final Response<Object?> response = await _dio(
        _engine(transport),
      ).get<Object?>('/users/42');

      expect(response.statusCode, 200);
      // dio DECODES the body itself when the adapter reports a JSON
      // content-type, so `response.data` is already a Map here — casting it to
      // String throws "_Map<String, dynamic> is not a subtype of String". That
      // decoding is the point: the adapter must set the content-type header
      // correctly or dio would hand the caller a raw string instead.
      expect(response.data, isA<Map<String, dynamic>>());
      expect((response.data! as Map<String, dynamic>)['who'], 'a');
      // The adapter must route through the BACKEND, not bypass it.
      expect(transport.sent, hasLength(1));
      expect(transport.sent.single.url.path, '/users/42');
    });

    test('dio request HEADERS reach the transport, stringified', () async {
      // `options.headers` is Map<String, Object?>; the adapter must coerce every
      // value to a String or a non-string header would be dropped or crash.
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest _) => okJson(<String, Object?>{'ok': true}),
      );

      await _dio(_engine(transport)).get<Object?>(
        '/thing',
        options: Options(
          headers: <String, Object?>{'x-trace': 'abc', 'x-attempt': 2},
        ),
      );

      final HttpRequest sent = transport.sent.single;
      expect(sent.headers['x-trace'], 'abc');
      expect(sent.headers['x-attempt'], '2', reason: 'coerced to String');
    });

    test('a MAP body is JSON-encoded on the way through', () async {
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest _) => okJson(<String, Object?>{'ok': true}),
      );

      await _dio(
        _engine(transport),
      ).post<Object?>('/thing', data: <String, Object?>{'a': 1});

      expect(jsonDecode(transport.sent.single.body!), <String, Object?>{
        'a': 1,
      });
    });

    test('a STRING body is passed through unchanged', () async {
      // The `options.data is String` branch — encoding it again would
      // double-encode a caller's pre-serialised payload.
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest _) => okJson(<String, Object?>{'ok': true}),
      );

      await _dio(_engine(transport)).post<Object?>(
        '/thing',
        data: '{"raw":true}',
        options: Options(contentType: Headers.jsonContentType),
      );

      expect(transport.sent.single.body, '{"raw":true}');
    });

    test('query parameters survive the round trip', () async {
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest _) => okJson(<String, Object?>{'ok': true}),
      );

      await _dio(
        _engine(transport),
      ).get<Object?>('/thing', queryParameters: <String, Object?>{'page': 2});

      expect(transport.sent.single.url.queryParameters['page'], '2');
    });

    test('a HARD network failure becomes a dio connectionError', () async {
      // The generated SDK sees a DioException; ResultSdk then maps it back to a
      // transport-failure Problem. Losing the reason here would strand the
      // caller with no diagnosis.
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest _) => networkFailure('primary refused'),
      );

      await expectLater(
        _dio(_engine(transport)).get<Object?>('/thing'),
        throwsA(
          isA<DioException>().having(
            (DioException e) => '${e.message} ${e.error}',
            'reason',
            contains('primary refused'),
          ),
        ),
      );
    });

    test('a TOKEN failure becomes a dio error carrying the Problem', () async {
      // The auth Problem must survive as `DioException.error` so ResultSdk can
      // surface it losslessly rather than reporting a generic transport fault.
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest _) => okJson(<String, Object?>{'ok': true}),
      );
      // FakeAuth with an EMPTY map fails closed for any key.
      final ApiEngine engine = _engine(
        transport,
        auth: FakeAuth(const <String, String>{}),
        resource: 'a',
      );

      try {
        await _dio(engine).get<Object?>('/thing');
        fail('expected a DioException carrying the auth Problem');
      } on DioException catch (error) {
        expect(error.error, isA<Problem>());
        expect((error.error! as Problem).status, 401);
      }
      // Fail-closed: the request must NOT have been sent without a token.
      expect(transport.sent, isEmpty);
    });

    test('an error status is returned as a response, not thrown', () async {
      // A RECEIVED 4xx is not a network failure. dio is configured by the
      // generated client to validate status, so the adapter's job is only to
      // hand the status back faithfully.
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest _) => Received(
          HttpResponse(
            status: 404,
            headers: const <String, String>{'content-type': 'application/json'},
            body: jsonEncode(<String, Object?>{'type': 'urn:x', 'status': 404}),
          ),
        ),
      );

      final Response<Object?> response = await _dio(_engine(transport))
          .get<Object?>(
            '/missing',
            options: Options(validateStatus: (int? _) => true),
          );

      expect(response.statusCode, 404);
    });

    test('close is a no-op and does not throw', () {
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest _) => okJson(<String, Object?>{'ok': true}),
      );
      final BackendClientAdapter adapter = BackendClientAdapter(
        _engine(transport).backend(_coord('a'))!,
      );

      // The adapter owns no socket — the Backend does — so closing must be safe
      // and must not tear down the shared transport.
      expect(adapter.close, returnsNormally);
      expect(() => adapter.close(force: true), returnsNormally);
    });
  });

  group('Backend.sdk wires a generated client through the adapter', () {
    test('the Dio handed to the factory is backed by this backend', () async {
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest _) => okJson(<String, Object?>{'via': 'sdk'}),
      );
      final Backend backend = _engine(transport).backend(_coord('a'))!;

      // This is the shape a generated retrofit client is constructed with.
      final Dio dio = backend.sdk<Dio>((Dio d) => d);
      final Response<Object?> response = await dio.get<Object?>('/sdk');

      expect(response.statusCode, 200);
      expect(transport.sent.single.url.path, '/sdk');
    });
  });

  group('adapter body fallbacks when there is NO request stream', () {
    // MEASURED: dio ALWAYS supplies a requestStream, so `fetch`'s two `else if`
    // branches are unreachable through a Dio client — line 262 is hit while 267
    // and 269 are not. They are defensive fallbacks for a caller that invokes
    // the adapter directly, which is legitimate (the adapter is a public export),
    // so they are covered by calling `fetch` directly rather than declared dead.
    Future<ResponseBody> fetchWith(Object? data, FakeHttpTransport t) {
      final BackendClientAdapter adapter = BackendClientAdapter(
        _engine(t).backend(_coord('a'))!,
      );
      return adapter.fetch(
        RequestOptions(path: '/thing', method: 'POST', data: data),
        null, // no request stream — the branch under test
        null,
      );
    }

    test('a STRING data payload is passed through unchanged', () async {
      final FakeHttpTransport t = FakeHttpTransport(
        (HttpRequest _) => okJson(<String, Object?>{'ok': true}),
      );

      await fetchWith('{"raw":true}', t);

      expect(t.sent.single.body, '{"raw":true}');
    });

    test('a NON-string data payload is JSON-encoded', () async {
      final FakeHttpTransport t = FakeHttpTransport(
        (HttpRequest _) => okJson(<String, Object?>{'ok': true}),
      );

      await fetchWith(<String, Object?>{'a': 1}, t);

      expect(jsonDecode(t.sent.single.body!), <String, Object?>{'a': 1});
    });

    test('a null data payload sends no body at all', () async {
      final FakeHttpTransport t = FakeHttpTransport(
        (HttpRequest _) => okJson(<String, Object?>{'ok': true}),
      );

      await fetchWith(null, t);

      expect(t.sent.single.body, isNull);
    });
  });
}
