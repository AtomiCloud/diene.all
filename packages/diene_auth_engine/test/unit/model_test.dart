import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:diene_auth_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final DateTime now = DateTime.utc(2026, 7, 21);

  group('Result / Option factories and helpers', () {
    test('factory ok/err and fold alias', () {
      expect((Result<int>.ok(1) as Success<int>).value, 1);
      expect(
        Result<int>.err(
          const Problem(type: 't', title: 'x', status: 400),
        ).isFailure,
        isTrue,
      );
      expect(
        const Success<int>(
          2,
        ).fold(onSuccess: (int v) => v, onFailure: (_) => 0),
        2,
      );
      expect(const Success<int>(2).problemOrNull, isNull);
    });

    test('Option some/none equality and helpers', () {
      expect(const Some<int>(1), const Some<int>(1));
      expect(const None<int>(), const None<int>());
      expect(Option<int>.some(1).valueOrNull, 1);
      expect(Option<int>.none().valueOrNull, isNull);
      expect(
        const Some<int>(3).match(onSome: (int v) => v, onNone: () => 0),
        3,
      );
    });
  });

  group('SessionTokens / ResourceToken', () {
    test('validity checks and equality', () {
      final SessionTokens tokens = AuthFixtures.sessionTokens(now: now);
      expect(tokens.accessValidAt(now), isTrue);
      expect(
        tokens.accessValidAt(now.add(const Duration(minutes: 11))),
        isFalse,
      );
      expect(tokens.refreshValidAt(now), isTrue);
      expect(tokens, AuthFixtures.sessionTokens(now: now));

      final ResourceToken token = AuthFixtures.resourceToken(
        now: now,
        jwtToken: 'j',
      );
      expect(token.validAt(now), isTrue);
      expect(token, AuthFixtures.resourceToken(now: now, jwtToken: 'j'));
    });
  });

  group('ResourceKey', () {
    test('rejects a non-DNS label', () {
      expect(
        () => ResourceKey(
          platform: 'BadCase',
          landscape: 'lapras',
          service: 'api',
          resourceName: 'root',
        ),
        throwsFormatException,
      );
    });

    test('equality is by mapKey + domain', () {
      expect(AuthFixtures.resourceKey(), AuthFixtures.resourceKey());
    });
  });

  group('DeviceInfo / RedeemResult', () {
    test('device json omits null optionals', () {
      const DeviceInfo device = DeviceInfo(platform: 'ios', appVersion: '1.2');
      final Map<String, Object?> json = device.toJson();
      expect(json['platform'], 'ios');
      expect(json['appVersion'], '1.2');
      expect(json.containsKey('osVersion'), isFalse);
    });

    test('redeem result defaults expiresIn to 120', () {
      const RedeemResult result = RedeemResult(token: 't', email: 'e');
      expect(result.expiresIn, 120);
    });
  });

  group('BackendRegistry / RegisteredBackend', () {
    final ResourceKey key = AuthFixtures.resourceKey();

    test('rejects a duplicate backend id', () {
      expect(
        () => BackendRegistry(<RegisteredBackend>[
          RegisteredBackend(
            backendId: 'a',
            resources: <ResourceKey>[key],
            onboardingResource: key,
          ),
          RegisteredBackend(
            backendId: 'a',
            resources: <ResourceKey>[key],
            onboardingResource: key,
          ),
        ]),
        throwsArgumentError,
      );
    });

    test('rejects an onboarding resource outside the resource list', () {
      expect(
        () => RegisteredBackend(
          backendId: 'a',
          resources: <ResourceKey>[key],
          onboardingResource: AuthFixtures.resourceKey(service: 'other'),
        ),
        throwsArgumentError,
      );
    });

    test('resourceUnion dedups across backends', () {
      final ResourceKey keyB = AuthFixtures.resourceKey(service: 'billing');
      final BackendRegistry registry = BackendRegistry(<RegisteredBackend>[
        RegisteredBackend(
          backendId: 'a',
          resources: <ResourceKey>[key],
          onboardingResource: key,
        ),
        RegisteredBackend(
          backendId: 'b',
          resources: <ResourceKey>[key, keyB],
          onboardingResource: keyB,
        ),
      ]);
      expect(registry.resourceUnion.length, 2);
      expect(registry.byId('a')?.backendId, 'a');
    });
  });
}
