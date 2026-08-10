namespace AtomiCloud.Diene.ApiEngine.Config;

/// <summary>A configuration field that failed validation, named so the fix is unambiguous.</summary>
/// <remarks>
/// Prefixed rather than named <c>ConfigError</c>: auth-engine already publishes that name in its
/// own <c>Config</c> namespace, so a consumer importing both engines would have to alias one of
/// them at every call site.
/// </remarks>
/// <param name="Field">The dotted path of the offending field.</param>
/// <param name="Reason">Why the value was rejected.</param>
public sealed record ApiConfigError(string Field, string Reason)
{
    /// <summary>Renders the failure as a single diagnostic line.</summary>
    public override string ToString() => $"{Field}: {Reason}";
}
