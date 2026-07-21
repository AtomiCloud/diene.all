import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/src/generated/export.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:test/test.dart';

ServiceSdk _sdk(HttpTransport transport) => ServiceSdk(
      OA3Adapter.dio(
        baseUrl: Uri.parse('https://service.example.com'),
        // Hot-path retry-once wraps the transport, exactly as a Backend would.
        transport: RetryOnceTransport(transport),
      ),
    );

void main() {
  group('OA3 SDK-wrapper boundary (toResult over a generated retrofit client)',
      () {
    test('200 JSON → Ok(typed model)', () async {
      final ServiceSdk sdk = _sdk(
        FakeHttpTransport.sequence(<TransportOutcome>[
          okJson(<String, Object?>{'id': '1', 'email': 'a@b.com'}),
        ]),
      );

      final Result<UserProfile> result =
          await const ResultSdk().call(() => sdk.users.getUser(id: '1'));

      final UserProfile user = expectOk(result);
      expect(user.id, '1');
      expect(user.email, 'a@b.com');
    });

    test('404 problem body → Err(that Problem)', () async {
      final ServiceSdk sdk = _sdk(
        FakeHttpTransport.sequence(<TransportOutcome>[
          problemResponse(problemFixture(
            type: 'urn:diene:problem:entity-not-found',
            status: 404,
          )),
        ]),
      );

      final Result<UserProfile> result =
          await const ResultSdk().call(() => sdk.users.getUser(id: '404'));

      expect(expectErr(result).type, 'urn:diene:problem:entity-not-found');
      expect(result.unwrapErr().status, 404);
    });

    test('retry-once then success → Ok', () async {
      final ServiceSdk sdk = _sdk(
        FakeHttpTransport.sequence(<TransportOutcome>[
          networkFailure('reset'),
          okJson(<String, Object?>{'id': '2', 'email': 'c@d.com'}),
        ]),
      );

      final Result<UserProfile> result =
          await const ResultSdk().call(() => sdk.users.getUser(id: '2'));

      expect(expectOk(result).id, '2');
    });

    test('hard network failure past retry-once → transport-failure Problem',
        () async {
      final ServiceSdk sdk = _sdk(
        FakeHttpTransport.sequence(<TransportOutcome>[
          networkFailure('reset'),
          networkFailure('reset'),
        ]),
      );

      final Result<UserProfile> result = await const ResultSdk().call(
        () => sdk.users.getUser(id: '3'),
        endpoint: 'users.getUser',
      );

      expectProblemType(result, BridgeProblems.transportFailure);
    });
  });
}
