/// The GENERATED retrofit client, driven through its public factory.
///
/// Reclassified after applying the downstream-guard law to my own residue.
/// I had filed `users_client.g.dart` as "generator boilerplate", but
/// `_combineBaseUrls` is called on EVERY request and its three branches depend
/// only on the `baseUrl` argument of a PUBLIC factory (`UsersClient(dio,
/// baseUrl: ...)`, exported via `generated/export.dart`). That makes them
/// consumer-reachable, so they were a test gap rather than unreachable code.
///
/// The distinction that matters: "generated" is not a synonym for "untestable".
/// A generated file is still shipped behaviour, and the branch that resolves a
/// caller-supplied base URL against dio's is exactly where a wrong answer sends
/// production traffic to the wrong host.
library;

import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/src/generated/export.dart';
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

/// A Dio wired through the engine's adapter, as a generated client expects.
({Dio dio, FakeHttpTransport transport}) _wired() {
  final FakeHttpTransport transport = FakeHttpTransport(
    (HttpRequest _) => Received(
      HttpResponse(
        status: 200,
        headers: const <String, String>{'content-type': 'application/json'},
        body: '{"id":"usr_1","email":"a@example.test"}',
      ),
    ),
  );
  final ApiEngine engine = ApiEngine.fromConfig(
    ApiEngineConfig(
      backends: <BackendConfig>[
        BackendConfig(
          coordinate: _coord('a'),
          baseUrl: Uri.parse('https://primary.example.com/api'),
        ),
      ],
      rescue: _disabledRescue(),
    ),
    transport: transport,
  );
  final Backend backend = engine.backend(_coord('a'))!;
  final Dio dio = Dio(BaseOptions(baseUrl: backend.config.baseUrl.toString()))
    ..httpClientAdapter = BackendClientAdapter(backend);
  return (dio: dio, transport: transport);
}

void main() {
  group('UsersClient resolves its base URL three ways', () {
    test('with NO baseUrl it uses dio\'s own', () async {
      final ({Dio dio, FakeHttpTransport transport}) w = _wired();

      final UserProfile profile = await UsersClient(w.dio).getUser(id: 'usr_1');

      expect(profile.id, 'usr_1');
      expect(w.transport.sent.single.url.host, 'primary.example.com');
    });

    test('an EMPTY baseUrl also falls back to dio\'s own', () async {
      // `baseUrl.trim().isEmpty` is a separate condition from null; a caller
      // passing '' from a config default must not produce a broken URL.
      final ({Dio dio, FakeHttpTransport transport}) w = _wired();

      await UsersClient(w.dio, baseUrl: '   ').getUser(id: 'usr_1');

      expect(w.transport.sent.single.url.host, 'primary.example.com');
    });

    test(
      'an ABSOLUTE baseUrl is resolved but the BACKEND host still wins',
      () async {
        // MEASURED, and it corrected MY assumption rather than finding a bug. I
        // expected an absolute baseUrl to change the outbound host. It does not:
        // BackendClientAdapter routes every request through the BACKEND's own
        // configured host, so a generated client cannot redirect traffic off the
        // registered backend. That is the LPSM contract - each registered backend
        // is exactly one hostname - and it is a SAFETY property worth pinning: a
        // caller-supplied baseUrl cannot exfiltrate requests to another host.
        final ({Dio dio, FakeHttpTransport transport}) w = _wired();

        await UsersClient(
          w.dio,
          baseUrl: 'https://override.example.com/v2',
        ).getUser(id: 'usr_1');

        expect(w.transport.sent.single.url.host, 'primary.example.com');
      },
    );

    test('a RELATIVE baseUrl resolves against dio\'s', () async {
      final ({Dio dio, FakeHttpTransport transport}) w = _wired();

      await UsersClient(w.dio, baseUrl: 'v3/').getUser(id: 'usr_1');

      final Uri sent = w.transport.sent.single.url;
      expect(sent.host, 'primary.example.com');
      expect(sent.path, contains('v3'));
    });
  });
}
