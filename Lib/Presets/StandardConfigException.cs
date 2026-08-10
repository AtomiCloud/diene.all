namespace AtomiCloud.Diene.StandardConfig.Presets;

/// <summary>
/// The library's own failure type, kept deliberately small.
/// </summary>
/// <remarks>
/// Config-shape failures are the config lib's job (its validators surface them at
/// <c>ValidateOnStart</c>); this type covers only the few imperative helpers here — the
/// fail-fast keyed lookup above all. It is an exception rather than a Problem because the
/// problems lib deliberately sits ABOVE this one in the DAG: standard-config needs
/// <c>config</c> only, and pulling in a problem catalogue to name a missing dictionary key
/// would invert that edge.
/// </remarks>
/// <param name="message">What went wrong.</param>
public sealed class StandardConfigException(string message) : Exception(message);
