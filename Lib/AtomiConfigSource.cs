namespace AtomiCloud.Diene.Config;

/// <summary>
/// Declares the three config layers of the C0 §3 precedence contract:
/// a required base file carrying full defaults, an optional sparse landscape
/// overlay, and prefixed environment variables applied LAST.
/// </summary>
/// <remarks>
/// There is no merge engine behind this record. The layers become
/// <see cref="Microsoft.Extensions.Configuration.IConfigurationProvider" />
/// instances in order, so provider layering IS the merge and validation runs
/// on the final merged layer only.
/// </remarks>
public sealed record AtomiConfigSource
{
    /// <summary>The base layer, carrying full defaults. Required — a missing base file is an error.</summary>
    public string BaseFile { get; init; } = "Config/settings.yaml";

    /// <summary>
    /// A composite format string for the sparse landscape overlay, where <c>{0}</c> is the
    /// landscape. The overlay is optional: an absent file simply contributes no layer.
    /// </summary>
    public string LandscapePattern { get; init; } = "Config/settings.{0}.yaml";

    /// <summary>
    /// The landscape whose overlay is applied. When left blank, it is resolved from the
    /// <c>LANDSCAPE</c> environment variable; when that is also blank, no overlay layer is added.
    /// </summary>
    public string Landscape { get; init; } = "";

    /// <summary>
    /// The environment-variable prefix for the final override layer. REQUIRED and deliberately
    /// without a baked default — the app or template supplies it (for example <c>ATOMI_</c>).
    /// </summary>
    /// <remarks>
    /// Under the prefix, <c>__</c> separates nesting levels and list elements use indexed keys
    /// (<c>FOO__0</c>, <c>FOO__1</c>, …). There is no JSON-in-env and no comma encoding.
    /// </remarks>
    public required string EnvPrefix { get; init; }

    /// <summary>
    /// Whether file layers are watched for changes. Always <see langword="false" /> in v1 —
    /// hot reload is deferred family-wide and setting this to <see langword="true" /> is rejected.
    /// </summary>
    public bool ReloadOnChange { get; init; }

    /// <summary>The environment variable consulted when <see cref="Landscape" /> is blank.</summary>
    public const string LandscapeVariable = "LANDSCAPE";
}
