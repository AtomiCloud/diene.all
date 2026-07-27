import 'dart:convert';

import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:diene_auth_engine/test_helper.dart';
import 'package:diene_result/diene_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Transport-level regressions for the HTTP redeem adapter. The C0 §7 contract is
// NO ORACLE: every non-success outcome — bad status, non-object body, missing or
// blank token, non-string email, transport throw — must collapse to the single
// AppHandoffExpired problem, so a caller can never distinguish "deleted" from
// "replayed" from "upstream down".
void main() {
  const DeviceInfo device = DeviceInfo(
    platform: 'ios',
    appVersion: '1.2.3',
    osVersion: '18.0',
    model: 'iPhone16,1',
  );

  HttpAppHandoffApi apiReturning(
    http.Response Function(http.Request) respond,
  ) => HttpAppHandoffApi(
    base: Uri.parse('https://api.lithium.lapras.cluster.atomi.cloud'),
    redeemPath: '/app-handoff/redeem',
    client: MockClient((http.Request request) async => respond(request)),
  );

  void expectExpired(Result<RedeemResult> result) {
    AuthExpect.status(
      AuthExpect.errType(result, 'urn:diene:problem:app-handoff-expired'),
      410,
    );
  }

  test('redeems a well-formed 200 into the minted one-time token', () async {
    // Arrange
    http.Request? seen;
    final HttpAppHandoffApi api = apiReturning((http.Request request) {
      seen = request;
      return http.Response(
        jsonEncode(<String, Object?>{
          'token': 'one-time-token',
          'email': 'trainer@atomi.cloud',
          'expiresIn': 90,
        }),
        200,
      );
    });

    // Act
    final Result<RedeemResult> result = await api.redeem(
      nonce: 'opaque-nonce',
      device: device,
    );

    // Assert — the redeem route is POST {mount}/redeem with a JSON envelope
    // carrying the nonce and the telemetry-only device block.
    expect(seen!.method, 'POST');
    expect(
      seen!.url.toString(),
      'https://api.lithium.lapras.cluster.atomi.cloud/app-handoff/redeem',
    );
    expect(seen!.headers['content-type'], contains('application/json'));
    final Map<String, Object?> sent =
        jsonDecode(seen!.body) as Map<String, Object?>;
    expect(sent['nonce'], 'opaque-nonce');
    expect(sent['device'], <String, Object?>{
      'platform': 'ios',
      'appVersion': '1.2.3',
      'osVersion': '18.0',
      'model': 'iPhone16,1',
    });

    final RedeemResult redeemed = AuthExpect.ok(result);
    expect(redeemed.token, 'one-time-token');
    expect(redeemed.email, 'trainer@atomi.cloud');
    expect(redeemed.expiresIn, 90);
  });

  test(
    'defaults expiresIn to the fixed 120s when absent or not an int',
    () async {
      // Arrange
      final HttpAppHandoffApi absent = apiReturning(
        (http.Request request) => http.Response(
          jsonEncode(<String, Object?>{'token': 't', 'email': 'e@x.io'}),
          200,
        ),
      );
      final HttpAppHandoffApi wrongType = apiReturning(
        (http.Request request) => http.Response(
          jsonEncode(<String, Object?>{
            'token': 't',
            'email': 'e@x.io',
            'expiresIn': 'soon',
          }),
          200,
        ),
      );

      // Act + Assert — C0 §7 fixes the one-time token lifetime at 120s.
      expect(
        AuthExpect.ok(
          await absent.redeem(nonce: 'n', device: device),
        ).expiresIn,
        AppHandoffConstants.oneTimeTokenExpiresInSeconds,
      );
      expect(
        AuthExpect.ok(
          await wrongType.redeem(nonce: 'n', device: device),
        ).expiresIn,
        AppHandoffConstants.oneTimeTokenExpiresInSeconds,
      );
    },
  );

  test(
    'accepts an empty-string email (identity resolution is upstream)',
    () async {
      // Arrange — only a NON-string email is malformed; a blank one is upstream's
      // business, so it must not be turned into a client-side oracle.
      final HttpAppHandoffApi api = apiReturning(
        (http.Request request) => http.Response(
          jsonEncode(<String, Object?>{'token': 't', 'email': ''}),
          200,
        ),
      );

      // Act + Assert
      expect(
        AuthExpect.ok(await api.redeem(nonce: 'n', device: device)).email,
        '',
      );
    },
  );

  test('collapses every non-success outcome to AppHandoffExpired', () async {
    // Arrange — one case per failure branch in the adapter.
    final Map<String, HttpAppHandoffApi> cases = <String, HttpAppHandoffApi>{
      'non-200 status': apiReturning(
        (http.Request request) => http.Response('gone', 410),
      ),
      'server error': apiReturning(
        (http.Request request) => http.Response('boom', 500),
      ),
      'body is not a JSON object': apiReturning(
        (http.Request request) => http.Response('["nope"]', 200),
      ),
      'body is not JSON at all': apiReturning(
        (http.Request request) => http.Response('<html>nope</html>', 200),
      ),
      'token missing': apiReturning(
        (http.Request request) => http.Response(
          jsonEncode(<String, Object?>{'email': 'e@x.io'}),
          200,
        ),
      ),
      'token blank': apiReturning(
        (http.Request request) => http.Response(
          jsonEncode(<String, Object?>{'token': '', 'email': 'e@x.io'}),
          200,
        ),
      ),
      'token not a string': apiReturning(
        (http.Request request) => http.Response(
          jsonEncode(<String, Object?>{'token': 7, 'email': 'e@x.io'}),
          200,
        ),
      ),
      'email not a string': apiReturning(
        (http.Request request) => http.Response(
          jsonEncode(<String, Object?>{'token': 't', 'email': 42}),
          200,
        ),
      ),
      'transport failure': apiReturning(
        (http.Request request) => throw http.ClientException('no route'),
      ),
    };

    // Act + Assert — indistinguishable outcomes, one problem.
    for (final MapEntry<String, HttpAppHandoffApi> entry in cases.entries) {
      expectExpired(await entry.value.redeem(nonce: 'n', device: device));
    }
  });

  test('joins the mount onto the base without doubling slashes', () async {
    // Arrange — the base carries a trailing slash AND the mount a leading one.
    final List<Uri> requested = <Uri>[];
    http.Client recorder() => MockClient((http.Request request) async {
      requested.add(request.url);
      return http.Response(
        jsonEncode(<String, Object?>{'token': 't', 'email': 'e@x.io'}),
        200,
      );
    });

    // Act
    await HttpAppHandoffApi(
      base: Uri.parse('https://api.lithium.lapras.cluster.atomi.cloud/'),
      redeemPath: '/app-handoff/redeem',
      client: recorder(),
    ).redeem(nonce: 'n', device: device);
    await HttpAppHandoffApi(
      base: Uri.parse('https://api.lithium.lapras.cluster.atomi.cloud'),
      redeemPath: 'app-handoff/redeem',
      client: recorder(),
    ).redeem(nonce: 'n', device: device);

    // Assert — both spellings resolve to the exact same route.
    expect(requested.map((Uri u) => u.path).toSet(), <String>{
      '/app-handoff/redeem',
    });
  });

  test('defaults to a real http.Client when none is injected', () {
    // Arrange + Act — construction must do NO network work.
    final HttpAppHandoffApi api = HttpAppHandoffApi(
      base: Uri.parse('https://api.lithium.lapras.cluster.atomi.cloud'),
      redeemPath: '${AppHandoffConstants.defaultMount}/redeem',
    );

    // Assert
    expect(api, isA<AppHandoffApi>());
  });
}
