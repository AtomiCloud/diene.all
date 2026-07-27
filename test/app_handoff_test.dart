import 'dart:convert';

import 'package:diene_flutter_base/auth/app_handoff.dart';
import 'package:diene_flutter_base/auth/deferred_login.dart';
import 'package:diene_flutter_base/auth/session_controller.dart';
import 'package:diene_flutter_base/core/result.dart';
import 'package:diene_flutter_base/onboarding/phase_machine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const String _nonce = 'wS3Xv7Qk1Lm9Zt0Ab2Cd4Ef6Gh8Ij0Kl2Mn4Op6Qr8x';
const String _carrier = '$appHandoffCarrierPrefix$_nonce';

const ResourceKey _apiResource = ResourceKey(
  platform: 'platform',
  landscape: 'lapras',
  service: 'service',
  resourceName: 'api',
);

final class _Carrier implements CarrierSource {
  _Carrier(this.raw);

  String? raw;

  @override
  CarrierChannel get channel => CarrierChannel.clipboard;

  @override
  Future<String?> readCarrier() async => raw;

  @override
  Future<void> markProcessed(String value) async => raw = null;
}

final class _SignIn implements ExtraParamsSignIn {
  _SignIn(this.now);

  final DateTime now;

  @override
  Future<SessionTokens> signInWithExtraParams(
    Map<String, String> extraParams,
  ) async => SessionTokens(
    accessToken: 'access-handoff',
    refreshToken: 'refresh-handoff',
    refreshFamily: 'handoff',
    accessExpiresAt: now.add(const Duration(minutes: 10)),
    refreshExpiresAt: now.add(const Duration(days: 14)),
  );
}

final class _Tokens implements TokenProvider {
  _Tokens({this.registered = true});

  final bool registered;

  @override
  Future<Map<ResourceKey, Result<ResourceToken>>> acquireAll(
    Set<ResourceKey> keys, {
    bool forceRefresh = false,
  }) async => <ResourceKey, Result<ResourceToken>>{
    for (final ResourceKey key in keys)
      key: Success<ResourceToken>(
        ResourceToken(
          raw: 'token-${key.mapKey}',
          claims: registered
              ? const <String, Object?>{'platform_service': 'true'}
              : const <String, Object?>{},
          expiresAt: DateTime.utc(2026, 7, 27, 10),
        ),
      ),
  };

  @override
  Future<String?> idToken() async => 'raw-id-token';
}

final class _OnboardClient implements OnboardSyncClient {
  int gets = 0;
  int posts = 0;

  @override
  Future<OnboardCallResult> getCurrentUser({
    required String backendId,
    required String accessToken,
  }) async {
    gets += 1;
    return const OnboardCallResult(200);
  }

  @override
  Future<OnboardCallResult> createUser({
    required String backendId,
    required String accessToken,
    required String idToken,
  }) async {
    posts += 1;
    return const OnboardCallResult(201);
  }
}

/// Whether onboarding actually ran, read off the real machine's own trace
/// rather than a spy — a machine that never ran has an empty trace.
bool _onboardingRan(OnboardingPhaseMachineSet set) =>
    set.machines.any((BackendPhaseMachine m) => m.trace.isNotEmpty);

AppHandoffRedeemClient _redeem({int status = 200}) => AppHandoffRedeemClient(
  mount: Uri.parse('https://api.example.invalid/app-handoff'),
  httpClient: MockClient((http.Request request) async {
    if (status != 200) {
      return http.Response('{}', status);
    }
    return http.Response(
      jsonEncode(<String, Object?>{
        'token': 'one-time-token',
        'email': 'user@example.invalid',
        'expiresIn': 120,
      }),
      200,
    );
  }),
);

DeferredLoginReceiver _receiver(DateTime now, {String? carrier = _carrier}) =>
    DeferredLoginReceiver(
      sources: <CarrierSource>[_Carrier(carrier)],
      ledger: NonceLedger(store: MemoryNonceLedgerStore()),
      redeemClient: _redeem(),
      signIn: _SignIn(now),
      device: const HandoffDevice(platform: 'ios'),
      now: () => now,
    );

OnboardingPhaseMachineSet _onboarding({bool registered = true}) =>
    OnboardingPhaseMachineSet(<BackendPhaseMachine>[
      BackendPhaseMachine(
        registration: const BackendRegistration(
          backendId: 'primary',
          resources: <ResourceKey>[_apiResource],
          onboardingResource: _apiResource,
        ),
        tokens: _Tokens(registered: registered),
        client: _OnboardClient(),
      ),
    ]);

void main() {
  final DateTime now = DateTime.utc(2026, 7, 27, 9);

  test('legal precedes onboarding on a fresh handoff arrival', () async {
    final MemoryLegalConsentGateway legal = MemoryLegalConsentGateway(
      now: () => now,
    );
    final OnboardingPhaseMachineSet onboarding = _onboarding();
    final AppHandoffFlow flow = AppHandoffFlow(
      receiver: _receiver(now),
      legal: legal,
      onboarding: onboarding,
      requiredTermsVersion: '2026-07-01',
      requiredPrivacyVersion: '2026-07-01',
    );

    final Result<HandoffArrival> result = await flow.arrive();

    final HandoffArrival arrival = (result as Success<HandoffArrival>).value;
    expect(arrival.deferredLogin.outcome, DeferredLoginOutcome.signedIn);
    expect(arrival.stages, <HandoffStage>[
      HandoffStage.identity,
      HandoffStage.legal,
      HandoffStage.onboarding,
      HandoffStage.ready,
    ]);
    expect(
      arrival.stages.indexOf(HandoffStage.legal),
      lessThan(arrival.stages.indexOf(HandoffStage.onboarding)),
    );
    expect(legal.presentations, 1);
    expect(arrival.consent!.termsVersion, '2026-07-01');
    expect(_onboardingRan(onboarding), isTrue);
    expect(arrival.phases, <String, BackendPhase>{
      'primary': BackendPhase.ready,
    });
  });

  test('declining the legal step blocks onboarding entirely', () async {
    final OnboardingPhaseMachineSet onboarding = _onboarding();
    final AppHandoffFlow flow = AppHandoffFlow(
      receiver: _receiver(now),
      legal: MemoryLegalConsentGateway(now: () => now, accepts: false),
      onboarding: onboarding,
      requiredTermsVersion: '2026-07-01',
      requiredPrivacyVersion: '2026-07-01',
    );

    final Result<HandoffArrival> result = await flow.arrive();

    expect(
      (result as Failure<HandoffArrival>).problem.type,
      'urn:diene:problem:legal-consent-declined',
    );
    expect(
      _onboardingRan(onboarding),
      isFalse,
      reason: 'onboarding must never have run',
    );
  });

  test('a consent already on file is not re-presented', () async {
    final MemoryLegalConsentGateway legal = MemoryLegalConsentGateway(
      now: () => now,
      stored: LegalConsent(
        termsVersion: '2026-07-01',
        privacyVersion: '2026-07-01',
        acceptedAt: now.subtract(const Duration(days: 30)),
      ),
    );
    final OnboardingPhaseMachineSet onboarding = _onboarding();
    final AppHandoffFlow flow = AppHandoffFlow(
      receiver: _receiver(now),
      legal: legal,
      onboarding: onboarding,
      requiredTermsVersion: '2026-07-01',
      requiredPrivacyVersion: '2026-07-01',
    );

    final Result<HandoffArrival> result = await flow.arrive();

    expect(result.isSuccess, isTrue);
    expect(legal.presentations, 0);
    expect(_onboardingRan(onboarding), isTrue);
  });

  test('a stale consent version is re-presented before onboarding', () async {
    final MemoryLegalConsentGateway legal = MemoryLegalConsentGateway(
      now: () => now,
      stored: LegalConsent(
        termsVersion: '2025-01-01',
        privacyVersion: '2026-07-01',
        acceptedAt: now.subtract(const Duration(days: 400)),
      ),
    );
    final AppHandoffFlow flow = AppHandoffFlow(
      receiver: _receiver(now),
      legal: legal,
      onboarding: _onboarding(),
      requiredTermsVersion: '2026-07-01',
      requiredPrivacyVersion: '2026-07-01',
    );

    final Result<HandoffArrival> result = await flow.arrive();

    expect(result.isSuccess, isTrue);
    expect(legal.presentations, 1);
    expect(
      (result as Success<HandoffArrival>).value.consent!.termsVersion,
      '2026-07-01',
    );
  });

  test('no carrier means no identity, so legal never runs', () async {
    final MemoryLegalConsentGateway legal = MemoryLegalConsentGateway(
      now: () => now,
    );
    final OnboardingPhaseMachineSet onboarding = _onboarding();
    final AppHandoffFlow flow = AppHandoffFlow(
      receiver: _receiver(now, carrier: null),
      legal: legal,
      onboarding: onboarding,
      requiredTermsVersion: '2026-07-01',
      requiredPrivacyVersion: '2026-07-01',
    );

    final Result<HandoffArrival> result = await flow.arrive();

    final HandoffArrival arrival = (result as Success<HandoffArrival>).value;
    expect(arrival.reachedStage, HandoffStage.identity);
    expect(
      arrival.deferredLogin.outcome,
      DeferredLoginOutcome.interactiveFallback,
    );
    expect(legal.presentations, 0);
    expect(_onboardingRan(onboarding), isFalse);
  });

  test('handoff is not an onboarding shortcut for a new user', () async {
    final OnboardingPhaseMachineSet onboarding = _onboarding(registered: false);
    final AppHandoffFlow flow = AppHandoffFlow(
      receiver: _receiver(now),
      legal: MemoryLegalConsentGateway(now: () => now),
      onboarding: onboarding,
      requiredTermsVersion: '2026-07-01',
      requiredPrivacyVersion: '2026-07-01',
    );

    final Result<HandoffArrival> result = await flow.arrive();

    final HandoffArrival arrival = (result as Success<HandoffArrival>).value;
    // Login succeeded, but the standard per-backend gate still ran and did not
    // reach ready — handoff establishes identity only.
    expect(arrival.deferredLogin.outcome, DeferredLoginOutcome.signedIn);
    expect(arrival.stages, contains(HandoffStage.onboarding));
    expect(arrival.stages, isNot(contains(HandoffStage.ready)));
    expect(_onboardingRan(onboarding), isTrue);
  });

  group('the ordering guard itself', () {
    final LegalConsent consent = LegalConsent(
      termsVersion: 'v1',
      privacyVersion: 'v1',
      acceptedAt: DateTime.utc(2026),
    );

    test('an onboarding-before-legal sequence is rejected', () {
      expect(
        () => AppHandoffFlow.assertLegalPrecedesOnboarding(
          <HandoffStage>[
            HandoffStage.identity,
            HandoffStage.onboarding,
            HandoffStage.legal,
          ],
          consent,
        ),
        throwsA(isA<LegalStepBypassed>()),
      );
    });

    test('onboarding with no legal stage at all is rejected', () {
      expect(
        () => AppHandoffFlow.assertLegalPrecedesOnboarding(
          <HandoffStage>[HandoffStage.identity, HandoffStage.onboarding],
          consent,
        ),
        throwsA(isA<LegalStepBypassed>()),
      );
    });

    test('a missing consent is rejected even in the right order', () {
      expect(
        () => AppHandoffFlow.assertLegalPrecedesOnboarding(
          <HandoffStage>[
            HandoffStage.identity,
            HandoffStage.legal,
            HandoffStage.onboarding,
          ],
          null,
        ),
        throwsA(isA<LegalStepBypassed>()),
      );
    });

    test('the correct order with a consent passes', () {
      expect(
        () => AppHandoffFlow.assertLegalPrecedesOnboarding(
          <HandoffStage>[
            HandoffStage.identity,
            HandoffStage.legal,
            HandoffStage.onboarding,
          ],
          consent,
        ),
        returnsNormally,
      );
    });
  });
}
