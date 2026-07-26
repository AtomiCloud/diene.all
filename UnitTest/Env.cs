namespace AtomiCloud.DotnetBase.UnitTest;

/// <summary>Builds the injected environment maps the precedence tests drive.</summary>
internal static class Env
{
    /// <summary>An environment with no OTEL_* variables set at all.</summary>
    public static IReadOnlyDictionary<string, string?> None { get; } =
        new Dictionary<string, string?>(StringComparer.Ordinal);

    /// <summary>An environment carrying exactly the given entries.</summary>
    public static IReadOnlyDictionary<string, string?> Of(params (string Name, string? Value)[] entries)
    {
        var environment = new Dictionary<string, string?>(StringComparer.Ordinal);
        foreach (var (name, value) in entries) environment[name] = value;
        return environment;
    }
}
