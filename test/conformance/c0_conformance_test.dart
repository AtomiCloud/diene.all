// NODE-LOCAL C0 CONTRACT CHECKS for the auth-engine surface (§5/§7/§8/§10/§12/
// §13). Dart is EXEMPT from the C0 otel config block (frontend-only; telemetry
// rides Faro).
//
// AUTHORITATIVE-FIXTURE BINDING IS INTEGRATION/REDESIGN-HELD (RB-315-class): no
// source-owned, versioned C0 conformance fixture exists yet for these sections
// — `goals/c0-contracts.md` ships contract PROSE, not a machine-readable fixture
// artifact, and shared-C0 fixture ownership is an open conductor REDESIGN. These
// assertions therefore encode the contract vectors LOCALLY and DO NOT claim to
// be backed by an authoritative fixture. Creating a package-local fixture and
// calling it authoritative is explicitly forbidden (it was the exact prior
// rejection). When the conductor materializes the versioned source-owned C0
// fixture set, these vectors must be re-pointed at it and its version/provenance
// recorded. See the node completion note, item P1c.
import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:diene_auth_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('C0 §5 Result semantics', () {
    test('Problem envelope round-trips through the wire form', () {
      // Arrange
      const Problem problem = Problem(
        type: 'urn:x',
        title: 't',
        status: 400,
        recoverable: true,
        data: <String, Object?>{'a': 1},
      );

      // Assert
      expect(Problem.fromJson(problem.toJson()), problem);
    });
  });

  group('C0 §8 onboarding claim rule', () {
    test('claim key is <platform>_<service>, dashes to underscores', () {
      expect(
        Claims.registrationKey(platform: 'li-th', service: 'ap-i'),
        'li_th_ap_i',
      );
    });

    test('registration requires the JSON string "true"', () {
      final Map<String, Object?> claims = Claims.decode(
        AuthFixtures.jwt(<String, Object?>{'lithium_api': 'true'}),
      );
      expect(
        Claims.hasRegistration(claims, platform: 'lithium', service: 'api'),
        isTrue,
      );
    });

    test('resource audience is the per-landscape LPSM identity', () {
      final ResourceKey key = AuthFixtures.resourceKey();
      expect(
        key.audience.toString(),
        'https://root.api.lithium.lapras.cluster.atomi.cloud',
      );
    });
  });

  group('C0 §7 app-handoff', () {
    test('carrier text is exactly atomi-app-handoff:v1:<nonce>', () {
      const String nonce = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC';
      final AppHandoffCarrier? carrier = AppHandoffCarrier.parseCanonical(
        'atomi-app-handoff:v1:$nonce',
      );
      expect(carrier?.canonicalText, 'atomi-app-handoff:v1:$nonce');
    });

    test('generic-expiry problem is AppHandoffExpired / 410', () {
      final Problem problem = appHandoffExpired();
      expect(problem.status, 410);
      expect(problem.title, 'App handoff expired');
    });

    test('fixed constants: nonce TTL 15m, one-time token 120s', () {
      expect(AppHandoffConstants.nonceTtl, const Duration(minutes: 15));
      expect(AppHandoffConstants.oneTimeTokenExpiresInSeconds, 120);
    });
  });

  group('C0 §12 token lifetimes', () {
    test('access = 10 minutes, refresh = 14 days', () {
      expect(TokenLifetimes.access, const Duration(minutes: 10));
      expect(TokenLifetimes.refresh, const Duration(days: 14));
    });
  });

  group('C0 §13 home claim', () {
    test('home_landscape claim is read from the token', () {
      final Map<String, Object?> claims = Claims.decode(
        AuthFixtures.jwt(<String, Object?>{Claims.homeLandscape: 'raichu'}),
      );
      expect(Claims.home(claims), 'raichu');
    });
  });

  group('C0 §10 Doc B — landscape selector', () {
    test('a Doc B leaking addresses/issuer is untrusted', () {
      expect(
        () => LandscapeSelectorDoc.fromJson(<String, Object?>{
          'platform': 'p',
          'tier': 't',
          'landscapes': <Object?>[
            <String, Object?>{'name': 'a', 'region': 'r', 'address': 'x'},
          ],
        }),
        throwsFormatException,
      );
    });
  });
}
