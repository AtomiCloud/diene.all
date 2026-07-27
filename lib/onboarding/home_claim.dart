/// The `home_landscape` claim (C0 §13) — checked on EVERY sign-in/sign-up.
///
/// Present → route straight to the home landscape; no Doc B fetch, no picker.
/// Absent → the pre-onboarding picker runs once, and OnboardSync writes the
/// claim back through the platform's own lithium Management API.
///
/// This claim is per-client-session ROUTING config. It is independent of the
/// per-backend `<platform>_<service>` registration claims in
/// [phase_machine.dart].
library;

import '../core/result.dart';

/// The custom-data / JWT claim key (C0 §13).
const String homeLandscapeClaimKey = 'home_landscape';

/// Reads the home claim from the current session's tokens and writes it back
/// through OnboardSync.
abstract interface class HomeLandscapeClaimGateway {
  /// The `home_landscape` claim on the current token, or null when absent.
  Future<String?> readHomeLandscapeClaim();

  /// Writes the claim via OnboardSync → Management API `custom_data`.
  Future<void> writeHomeLandscapeClaim(String landscape);
}

/// In-memory [HomeLandscapeClaimGateway] for tests and demo builds.
final class MemoryHomeLandscapeClaimGateway
    implements HomeLandscapeClaimGateway {
  MemoryHomeLandscapeClaimGateway({this.claim});

  String? claim;
  int reads = 0;
  int writes = 0;

  @override
  Future<String?> readHomeLandscapeClaim() async {
    reads += 1;
    return claim;
  }

  @override
  Future<void> writeHomeLandscapeClaim(String landscape) async {
    writes += 1;
    claim = landscape;
  }
}

/// How the home landscape for this session was decided.
enum HomeClaimSource { existingClaim, picker }

/// The resolved home landscape plus how it was reached.
final class HomeClaimResolution {
  const HomeClaimResolution({
    required this.landscape,
    required this.source,
    required this.pickerShown,
  });

  final String landscape;
  final HomeClaimSource source;

  /// True only when the picker was actually presented. Showing the picker with
  /// an existing claim is the sabotage the picker/home-claim gate catches.
  final bool pickerShown;
}

/// Raised when a picker run is attempted despite an existing home claim.
final class PickerShownWithExistingClaim implements Exception {
  const PickerShownWithExistingClaim(this.existingClaim);

  final String existingClaim;

  @override
  String toString() =>
      'PickerShownWithExistingClaim: home claim "$existingClaim" already '
      'exists; the picker must not run';
}

/// Runs the pre-onboarding picker. Implementations fetch Doc B, ping the
/// listed regions, and let the user (or the system) pick.
abstract interface class HomeLandscapePicker {
  Future<Result<String>> pickHomeLandscape();
}

/// Checks the home claim on every sign-in and only then decides whether the
/// picker runs (C0 §13).
final class HomeClaimCheck {
  const HomeClaimCheck({required this.gateway, required this.picker});

  final HomeLandscapeClaimGateway gateway;
  final HomeLandscapePicker picker;

  Future<Result<HomeClaimResolution>> resolveForSignIn() async {
    final String? existing;
    try {
      existing = await gateway.readHomeLandscapeClaim();
    } on Object catch (error) {
      return Failure<HomeClaimResolution>(
        Problem(
          type: 'urn:diene:problem:home-claim',
          title: 'Could not read the home landscape claim',
          status: 503,
          detail: error.toString(),
          recoverable: true,
        ),
      );
    }

    if (existing != null && existing.isNotEmpty) {
      // Present → straight through. The picker is never constructed a second
      // time for this user.
      return Success<HomeClaimResolution>(
        HomeClaimResolution(
          landscape: existing,
          source: HomeClaimSource.existingClaim,
          pickerShown: false,
        ),
      );
    }

    final Result<String> picked = await picker.pickHomeLandscape();
    if (picked is Failure<String>) {
      return Failure<HomeClaimResolution>(picked.problem);
    }
    final String landscape = (picked as Success<String>).value;
    try {
      await gateway.writeHomeLandscapeClaim(landscape);
    } on Object catch (error) {
      return Failure<HomeClaimResolution>(
        Problem(
          type: 'urn:diene:problem:home-claim-write',
          title: 'Could not write the home landscape claim',
          status: 503,
          detail: error.toString(),
          recoverable: true,
        ),
      );
    }
    return Success<HomeClaimResolution>(
      HomeClaimResolution(
        landscape: landscape,
        source: HomeClaimSource.picker,
        pickerShown: true,
      ),
    );
  }

  /// Structural assertion for callers that route on a resolution: the picker
  /// must never have been shown when a claim already existed.
  static void assertPickerNotShownWithClaim(
    String? existingClaim,
    HomeClaimResolution resolution,
  ) {
    if (existingClaim != null &&
        existingClaim.isNotEmpty &&
        resolution.pickerShown) {
      throw PickerShownWithExistingClaim(existingClaim);
    }
  }
}
