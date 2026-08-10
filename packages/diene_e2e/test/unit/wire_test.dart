import 'package:diene_e2e/diene_e2e.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppHandoffMint', () {
    test('toJson/fromJson round-trips', () {
      // Arrange.
      const AppHandoffMint mint = AppHandoffMint(
        nonce: 'abc',
        expiresAt: '2026-07-21T00:00:00Z',
      );
      // Act.
      final AppHandoffMint back = AppHandoffMint.fromJson(mint.toJson());
      // Assert.
      expect(back.nonce, 'abc');
      expect(back.expiresAt, '2026-07-21T00:00:00Z');
    });
  });

  group('AppHandoffRedeemRequest', () {
    test('omits null optional device fields but keeps platform', () {
      // Arrange.
      const AppHandoffRedeemRequest req = AppHandoffRedeemRequest(
        nonce: 'abc',
        device: AppHandoffDevice(platform: 'android'),
      );
      // Act.
      final Map<String, Object?> json = req.toJson();
      final Map<String, Object?> device =
          json['device']! as Map<String, Object?>;
      // Assert.
      expect(device['platform'], 'android');
      expect(device.containsKey('appVersion'), isFalse);
      expect(AppHandoffRedeemRequest.fromJson(json).device.platform, 'android');
    });
  });

  group('AppHandoffRedeemResponse', () {
    test('expiresIn defaults to the fixed 120s', () {
      const AppHandoffRedeemResponse resp = AppHandoffRedeemResponse(
        token: 't',
        email: 'a@b.com',
      );
      expect(resp.expiresIn, appHandoffTokenExpiresInSeconds);
      expect(resp.expiresIn, 120);
    });

    test('round-trips through json', () {
      const AppHandoffRedeemResponse resp = AppHandoffRedeemResponse(
        token: 't',
        email: 'a@b.com',
      );
      final AppHandoffRedeemResponse back = AppHandoffRedeemResponse.fromJson(
        resp.toJson(),
      );
      expect(back.token, 't');
      expect(back.email, 'a@b.com');
      expect(back.expiresIn, 120);
    });
  });

  group('AppHandoffExpired', () {
    test('carries the fixed no-oracle 410 body with injected type uri', () {
      // Arrange.
      final AppHandoffExpired problem = AppHandoffExpired.withType(
        'https://example/AppHandoffExpired',
      );
      // Act.
      final Map<String, Object?> json = problem.toJson();
      // Assert.
      expect(json['status'], 410);
      expect(json['title'], 'App handoff expired');
      expect(json['detail'], 'This app handoff is expired or invalid.');
      expect(json['data'], isEmpty);
      expect(json['type'], 'https://example/AppHandoffExpired');
      expect(AppHandoffExpired.status, 410);
      expect(AppHandoffExpired.problemId, 'AppHandoffExpired');
    });
  });
}
