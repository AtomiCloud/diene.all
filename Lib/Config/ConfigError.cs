namespace AtomiCloud.Diene.AuthEngine.Config;

/// <summary>A configuration field that failed validation, named so the fix is unambiguous.</summary>
/// <param name="Field">The dotted path of the offending field.</param>
/// <param name="Reason">Why the value was rejected.</param>
public sealed record ConfigError(string Field, string Reason)
{
    /// <summary>Renders the failure as a single diagnostic line.</summary>
    public override string ToString() => $"{this.Field}: {this.Reason}";
}
