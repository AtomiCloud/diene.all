using FluentValidation;

namespace AtomiCloud.DotnetBase.App;

/// <summary>
/// An engine-owned config block, exported next to the code that reads it.
/// </summary>
/// <remarks>
/// This is the shape every engine lib follows: the block and its validator live with the
/// engine, and the service composes it into its root schema with one registration line. The
/// config lib never knows what blocks exist — it only merges, validates, and serves them.
/// </remarks>
public sealed class ErrorPortalOption
{
    /// <summary>The config key this block binds to, authored as <c>error_portal</c> in YAML.</summary>
    public const string Key = "ErrorPortal";

    /// <summary>URI scheme of the published error portal.</summary>
    public string Scheme { get; set; } = "";

    /// <summary>Host serving the error portal.</summary>
    public string Host { get; set; } = "";

    /// <summary>Blank in YAML, injected from the environment per landscape.</summary>
    public string SigningKey { get; set; } = "";

    /// <summary>Fallback hosts, authored as a YAML list and overridable by indexed env keys.</summary>
    public IReadOnlyList<string> RetryHosts { get; set; } = [];
}

/// <summary>Validates <see cref="ErrorPortalOption" /> on the FINAL merged layer, at startup.</summary>
public sealed class ErrorPortalOptionValidator : AbstractValidator<ErrorPortalOption>
{
    /// <summary>Declares the rules.</summary>
    public ErrorPortalOptionValidator()
    {
        RuleFor(option => option.Scheme).Must(scheme => scheme is "http" or "https")
            .WithMessage("must be http or https");
        RuleFor(option => option.Host).NotEmpty();

        // The secret is blank in YAML and MUST be supplied by the environment. Requiring it
        // here is what turns a missing injection into a startup failure instead of a 500.
        RuleFor(option => option.SigningKey).NotEmpty()
            .WithMessage("is blank in YAML and must be injected from the environment");
        RuleFor(option => option.RetryHosts).NotEmpty();
    }
}
