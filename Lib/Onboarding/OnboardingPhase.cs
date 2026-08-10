namespace AtomiCloud.Diene.AuthEngine.Onboarding;

/// <summary>
/// Where a signed-in user sits in the home-landscape onboarding machine.
/// </summary>
/// <remarks>
/// The phases follow the claims-first order: inspect the backend claim, and only for an
/// absent claim fall through to the selector, the pick, and the sync that writes it.
/// </remarks>
public enum OnboardingPhase
{
    /// <summary>The home-landscape claim is present; route straight to the home landscape.</summary>
    Complete = 0,

    /// <summary>No claim; the user must be shown the landscape selector.</summary>
    SelectLandscape = 1,

    /// <summary>A landscape has been picked but the claim has not been written yet.</summary>
    AwaitingSync = 2,
}
