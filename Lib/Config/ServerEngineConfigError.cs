namespace AtomiCloud.Diene.ServerEngine.Config;

/// <summary>A configuration field that failed validation, named so the fix is unambiguous.</summary>
/// <remarks>
/// The type name carries the package name rather than being a plain <c>ConfigError</c>. Every
/// Diene engine package owns its own configuration block, so a service that composes two of them
/// — which is the normal case — would otherwise have to alias one of two identically-named types
/// in the same file. The demo consumer in this repository hit exactly that before the rename.
/// </remarks>
/// <param name="Field">The dotted path of the offending field.</param>
/// <param name="Reason">Why the value was rejected.</param>
public sealed record ServerEngineConfigError(string Field, string Reason)
{
    /// <summary>Renders the failure as a single diagnostic line.</summary>
    public override string ToString() => $"{this.Field}: {this.Reason}";
}
