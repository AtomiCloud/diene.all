import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:diene_auth_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const String nonce = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
  const String canonical = 'atomi-app-handoff:v1:$nonce';
  const DeviceInfo device = DeviceInfo(platform: 'android');

  test(
    'Android referrer wins, redeems, and returns signIn extraParams',
    () async {
      // Arrange
      final FakeInstallReferrerSource referrer = FakeInstallReferrerSource(
        'app_handoff=${Uri.encodeComponent(canonical)}',
      );
      final FakeAppHandoffApi api = FakeAppHandoffApi(
        result: const Success<RedeemResult>(
          RedeemResult(token: 'ott', email: 'a@b.co'),
        ),
      );
      final DeferredLoginClient client = DeferredLoginClient(
        api: api,
        device: device,
        referrer: referrer,
      );

      // Act
      final DeferredLoginOutcome outcome = await client.prepare();

      // Assert
      expect(outcome, isA<DeferredLoginReady>());
      final Map<String, String> params =
          (outcome as DeferredLoginReady).extraParams;
      expect(params['one_time_token'], 'ott');
      expect(params['login_hint'], 'a@b.co');
      expect(referrer.processed, isTrue);
      expect(api.lastNonce, nonce);
    },
  );

  test('iOS clipboard redeems and clears the clipboard', () async {
    // Arrange
    final FakeClipboardCarrierSource clipboard = FakeClipboardCarrierSource(
      '  $canonical ',
    );
    final DeferredLoginClient client = DeferredLoginClient(
      api: FakeAppHandoffApi(
        result: const Success<RedeemResult>(
          RedeemResult(token: 'ott', email: 'a@b.co'),
        ),
      ),
      device: const DeviceInfo(platform: 'ios'),
      clipboard: clipboard,
    );

    // Act
    final DeferredLoginOutcome outcome = await client.prepare();

    // Assert
    expect(outcome, isA<DeferredLoginReady>());
    expect(clipboard.cleared, isTrue);
  });

  test('no carrier falls back to interactive login', () async {
    // Arrange
    final DeferredLoginClient client = DeferredLoginClient(
      api: FakeAppHandoffApi(),
      device: device,
      referrer: FakeInstallReferrerSource(null),
      clipboard: FakeClipboardCarrierSource(null),
    );

    // Act
    final DeferredLoginOutcome outcome = await client.prepare();

    // Assert
    expect(outcome, isA<DeferredLoginFallback>());
    expect((outcome as DeferredLoginFallback).problem, isNull);
  });

  test('redeem failure falls back with the generic-expiry problem', () async {
    // Arrange
    final DeferredLoginClient client = DeferredLoginClient(
      api: FakeAppHandoffApi(), // defaults to AppHandoffExpired
      device: device,
      referrer: FakeInstallReferrerSource(
        'app_handoff=${Uri.encodeComponent(canonical)}',
      ),
    );

    // Act
    final DeferredLoginOutcome outcome = await client.prepare();

    // Assert
    final DeferredLoginFallback fallback = outcome as DeferredLoginFallback;
    expect(fallback.problem?.status, 410);
  });

  test('invalid carrier falls back without redeeming', () async {
    // Arrange
    final FakeAppHandoffApi api = FakeAppHandoffApi();
    final DeferredLoginClient client = DeferredLoginClient(
      api: api,
      device: device,
      referrer: FakeInstallReferrerSource('app_handoff=garbage'),
    );

    // Act
    final DeferredLoginOutcome outcome = await client.prepare();

    // Assert
    expect(outcome, isA<DeferredLoginFallback>());
    expect(api.redeemCount, 0);
  });
}
