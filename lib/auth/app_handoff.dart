/// App-handoff arrival flow: deferred login establishes IDENTITY only, then a
/// legal/consent step runs, and only then does onboarding start.
///
/// Handoff is not an onboarding shortcut (goals/deferred-login.md, "Handoff x
/// onboarding"). This file encodes the ordering as a machine-checked sequence
/// so bypassing the legal step is structurally impossible rather than merely
/// discouraged.
library;

import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';
import '../onboarding/phase_machine.dart';
import 'deferred_login.dart';

/// The ordered stages of a handoff arrival.
enum HandoffStage { identity, legal, onboarding, ready }

/// Consent the user must give before onboarding may run.
final class LegalConsent {
  const LegalConsent({
    required this.termsVersion,
    required this.privacyVersion,
    required this.acceptedAt,
  });

  final String termsVersion;
  final String privacyVersion;
  final DateTime acceptedAt;
}

/// Presents the legal/consent step and records the answer.
abstract interface class LegalConsentGateway {
  /// The consent already on file, or null when the user has never accepted.
  Future<LegalConsent?> readConsent();

  /// Shows the legal step. Returns null when the user declines.
  Future<LegalConsent?> presentLegalStep({
    required String requiredTermsVersion,
    required String requiredPrivacyVersion,
  });
}

/// In-memory [LegalConsentGateway] used by tests and demo builds.
final class MemoryLegalConsentGateway implements LegalConsentGateway {
  MemoryLegalConsentGateway({
    required this.now,
    this.stored,
    this.accepts = true,
  });

  final DateTime Function() now;
  LegalConsent? stored;
  bool accepts;
  int presentations = 0;

  @override
  Future<LegalConsent?> readConsent() async => stored;

  @override
  Future<LegalConsent?> presentLegalStep({
    required String requiredTermsVersion,
    required String requiredPrivacyVersion,
  }) async {
    presentations += 1;
    if (!accepts) {
      return null;
    }
    final LegalConsent consent = LegalConsent(
      termsVersion: requiredTermsVersion,
      privacyVersion: requiredPrivacyVersion,
      acceptedAt: now().toUtc(),
    );
    stored = consent;
    return consent;
  }
}

/// Result of one handoff arrival.
final class HandoffArrival {
  const HandoffArrival({
    required this.reachedStage,
    required this.stages,
    required this.deferredLogin,
    this.consent,
    this.phases,
  });

  /// The furthest stage reached.
  final HandoffStage reachedStage;

  /// Stages entered, in order. The onboarding stage can never appear before
  /// the legal stage — that ordering is the gate.
  final List<HandoffStage> stages;

  final DeferredLoginReport deferredLogin;
  final LegalConsent? consent;

  /// Per-backend phases once onboarding ran, otherwise null.
  final Map<String, BackendPhase>? phases;
}

/// Raised when an arrival tries to onboard without a recorded consent.
final class LegalStepBypassed implements Exception {
  const LegalStepBypassed(this.detail);

  final String detail;

  @override
  String toString() => 'LegalStepBypassed: $detail';
}

/// Drives identity → legal → onboarding for a handoff arrival.
final class AppHandoffFlow {
  const AppHandoffFlow({
    required this.receiver,
    required this.legal,
    required this.onboarding,
    required this.requiredTermsVersion,
    required this.requiredPrivacyVersion,
  });

  final DeferredLoginReceiver receiver;
  final LegalConsentGateway legal;
  final OnboardingPhaseMachineSet onboarding;
  final String requiredTermsVersion;
  final String requiredPrivacyVersion;

  Future<Result<HandoffArrival>> arrive() async {
    final List<HandoffStage> stages = <HandoffStage>[HandoffStage.identity];
    final DeferredLoginReport login = await receiver.attempt();
    if (login.outcome != DeferredLoginOutcome.signedIn) {
      // No identity yet: interactive login takes over. Legal and onboarding
      // both stay unreached.
      return Ok<HandoffArrival>(
        HandoffArrival(
          reachedStage: HandoffStage.identity,
          stages: stages,
          deferredLogin: login,
        ),
      );
    }

    stages.add(HandoffStage.legal);
    final LegalConsent? consent = await _resolveConsent();
    if (consent == null) {
      return const Err<HandoffArrival>(
        Problem(
          type: 'urn:diene:problem:legal-consent-declined',
          title: 'Legal consent is required',
          status: 403,
          detail:
              'Onboarding cannot start until the legal step is accepted.',
          recoverable: true,
        ),
      );
    }

    stages.add(HandoffStage.onboarding);
    // Structural guard: onboarding is unreachable without a consent in hand.
    assertLegalPrecedesOnboarding(stages, consent);
    final Map<String, BackendPhase> phases = await onboarding.runAll();

    final bool allReady = phases.values.every(
      (BackendPhase phase) => phase == BackendPhase.ready,
    );
    if (allReady) {
      stages.add(HandoffStage.ready);
    }
    return Ok<HandoffArrival>(
      HandoffArrival(
        reachedStage: stages.last,
        stages: stages,
        deferredLogin: login,
        consent: consent,
        phases: phases,
      ),
    );
  }

  Future<LegalConsent?> _resolveConsent() async {
    final LegalConsent? existing = await legal.readConsent();
    if (existing != null &&
        existing.termsVersion == requiredTermsVersion &&
        existing.privacyVersion == requiredPrivacyVersion) {
      return existing;
    }
    return legal.presentLegalStep(
      requiredTermsVersion: requiredTermsVersion,
      requiredPrivacyVersion: requiredPrivacyVersion,
    );
  }

  /// The ordering guard.
  ///
  /// Static so a test can prove it rejects a bypass directly, without having to
  /// construct a whole bypassing flow. Throws [LegalStepBypassed] unless a
  /// consent exists AND the legal stage was entered before the onboarding one.
  static void assertLegalPrecedesOnboarding(
    List<HandoffStage> stages,
    LegalConsent? consent,
  ) {
    final int legalAt = stages.indexOf(HandoffStage.legal);
    final int onboardingAt = stages.indexOf(HandoffStage.onboarding);
    if (consent == null || legalAt < 0 || legalAt > onboardingAt) {
      throw const LegalStepBypassed(
        'legal/consent must be recorded before onboarding starts',
      );
    }
  }
}
