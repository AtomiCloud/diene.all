import '../core/result.dart';

abstract interface class HomeClaimGateway {
  Future<String?> readHomeClaim();
  Future<void> writeHomeClaim(String landscape);
}

final class SingleRegionHomePicker {
  const SingleRegionHomePicker({
    required this.gateway,
    required this.landscape,
  });

  final HomeClaimGateway gateway;
  final String landscape;

  Future<Result<String>> resolve() async {
    try {
      final String? current = await gateway.readHomeClaim();
      if (current != null && current.isNotEmpty) {
        return Success<String>(current);
      }
      await gateway.writeHomeClaim(landscape);
      return Success<String>(landscape);
    } on Object catch (error) {
      return Failure<String>(
        Problem(
          type: 'urn:diene:problem:home-claim',
          title: 'Could not verify the home landscape',
          status: 503,
          detail: error.toString(),
          recoverable: true,
        ),
      );
    }
  }
}

enum UserProbeResult { present, absent }

abstract interface class OnboardingGateway {
  Future<UserProbeResult> probeCurrentUser(String backendId);
  Future<void> synchronizeCurrentUser(String backendId);
}

enum OnboardingPhase { checkingHome, probing, synchronizing, ready, failed }

final class OnboardingCoordinator {
  OnboardingCoordinator({
    required this.homePicker,
    required this.gateway,
    required this.backendId,
  });

  final SingleRegionHomePicker homePicker;
  final OnboardingGateway gateway;
  final String backendId;
  OnboardingPhase phase = OnboardingPhase.checkingHome;

  Future<Result<OnboardingPhase>> runAfterSignIn() async {
    phase = OnboardingPhase.checkingHome;
    final Result<String> home = await homePicker.resolve();
    if (home is Failure<String>) {
      phase = OnboardingPhase.failed;
      return Failure<OnboardingPhase>(home.problem);
    }
    try {
      phase = OnboardingPhase.probing;
      final UserProbeResult result = await gateway.probeCurrentUser(backendId);
      if (result == UserProbeResult.absent) {
        phase = OnboardingPhase.synchronizing;
        await gateway.synchronizeCurrentUser(backendId);
      }
      phase = OnboardingPhase.ready;
      return Success<OnboardingPhase>(phase);
    } on Object catch (error) {
      phase = OnboardingPhase.failed;
      return Failure<OnboardingPhase>(
        Problem(
          type: 'urn:diene:problem:onboarding',
          title: 'Onboarding could not complete',
          status: 503,
          detail: error.toString(),
          recoverable: true,
        ),
      );
    }
  }
}

final class MemoryHomeClaimGateway implements HomeClaimGateway {
  String? value;

  @override
  Future<String?> readHomeClaim() async => value;

  @override
  Future<void> writeHomeClaim(String landscape) async {
    value = landscape;
  }
}

final class DemoOnboardingGateway implements OnboardingGateway {
  bool synchronized = false;

  @override
  Future<UserProbeResult> probeCurrentUser(String backendId) async =>
      synchronized ? UserProbeResult.present : UserProbeResult.absent;

  @override
  Future<void> synchronizeCurrentUser(String backendId) async {
    synchronized = true;
  }
}
