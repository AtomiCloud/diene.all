/// `IoHttpTransport`'s remaining socket-level error classes.
///
/// I first classified these as integration-grade — "provoking real TLS/HTTP
/// protocol faults needs a misconfigured TLS server". That was too pessimistic,
/// and a probe disproved it: both are reachable from a loopback server in
/// milliseconds. Measured before writing the tests:
///
///   https:// against a PLAIN-http server -> tls: Connection terminated during handshake
///   a socket emitting non-HTTP bytes      -> http: Invalid response line
///
/// The property under test is the transport's contract: it NEVER throws. Every
/// hard failure is returned as data so the engine can decide whether to retry or
/// hand off to the rescue router.
library;

import 'dart:io' as io;

import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IoHttpTransport maps protocol-level faults to NetworkFailure', () {
    test(
      'a TLS handshake against a plain-HTTP server is a NetworkFailure',
      () async {
        // A server speaking cleartext while the client expects TLS: the handshake
        // dies rather than the connection being refused, so this reaches the
        // HandshakeException arm rather than the SocketException one.
        final io.HttpServer plain = await io.HttpServer.bind(
          io.InternetAddress.loopbackIPv4,
          0,
        );
        plain.listen((io.HttpRequest r) async {
          r.response.statusCode = 200;
          await r.response.close();
        });
        addTearDown(() => plain.close(force: true));

        final IoHttpTransport transport = IoHttpTransport(
          timeout: const Duration(seconds: 3),
        );
        addTearDown(transport.close);

        final TransportOutcome outcome = await transport.send(
          HttpRequest(
            method: HttpMethod.get,
            url: Uri.parse('https://127.0.0.1:${plain.port}/x'),
          ),
        );

        expect(outcome, isA<NetworkFailure>());
        // The reason must name the CLASS of fault, or a caller reading logs cannot
        // tell a TLS misconfiguration from a refused port.
        expect((outcome as NetworkFailure).reason, startsWith('tls: '));
        expect(outcome.cause, isNotNull);
      },
    );

    test('a non-HTTP response body is a NetworkFailure, not a throw', () async {
      // A socket that answers with garbage instead of a status line. The
      // transport must classify it rather than letting HttpException escape into
      // the caller's request path.
      final io.ServerSocket raw = await io.ServerSocket.bind(
        io.InternetAddress.loopbackIPv4,
        0,
      );
      raw.listen((io.Socket s) {
        s.write('NOT-HTTP\r\n\r\n');
        s.destroy();
      });
      addTearDown(raw.close);

      final IoHttpTransport transport = IoHttpTransport(
        timeout: const Duration(seconds: 3),
      );
      addTearDown(transport.close);

      final TransportOutcome outcome = await transport.send(
        HttpRequest(
          method: HttpMethod.get,
          url: Uri.parse('http://127.0.0.1:${raw.port}/x'),
        ),
      );

      expect(outcome, isA<NetworkFailure>());
      expect((outcome as NetworkFailure).reason, startsWith('http: '));
      expect(outcome.cause, isNotNull);
    });
  });
}
