using AtomiCloud.Diene.AuthEngine.Onboarding;

namespace AtomiCloud.Diene.ServerEngine.Onboarding;

/// <summary>Where the caller sits in the home-landscape onboarding machine.</summary>
/// <param name="Phase">
/// The phase, on the wire as its snake_case name — <c>complete</c>,
/// <c>select_landscape</c>, or <c>awaiting_sync</c>.
/// </param>
public sealed record OnboardSyncPhaseView(OnboardingPhase Phase);

/// <summary>The landscape the caller picked in the selector.</summary>
/// <param name="Landscape">The picked landscape name.</param>
public sealed record OnboardSyncCompleteRequest(string? Landscape);
