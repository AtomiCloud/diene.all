using AtomiCloud.Diene.CoreUtils;
using AtomiCloud.Diene.ServerEngine.Config;
using FluentValidation;

namespace AtomiCloud.DotnetBase.App.Options;

/// <summary>
/// The <c>server_engine:</c> block. Holds only what the service owns; the identity half of
/// <see cref="ServerEngineConfig"/> is derived from the mandatory <c>app:</c> block so the two
/// cannot drift.
/// </summary>
public sealed class ServerOption
{
    /// <summary>Configuration key this block binds to.</summary>
    public const string Key = ServerEngineConfig.Key;

    /// <summary>
    /// Signature freshness window for inbound webhook deliveries, as an ISO 8601 duration.
    /// The engine refuses anything above its own maximum rather than clamping it.
    /// </summary>
    public string WebhookTolerance { get; set; } = "PT5M";

    /// <summary>
    /// Live webhook signing keys. Blank in YAML and injected per landscape. During a rotation
    /// BOTH the outgoing and the incoming key must be present or in-flight deliveries are rejected.
    /// </summary>
    public IList<string> WebhookSigningKeys { get; set; } = [];
}

/// <summary>Validates <see cref="ServerOption"/> on the final merged configuration layer.</summary>
public sealed class ServerOptionValidator : AbstractValidator<ServerOption>
{
    /// <summary>Declares the block's rules.</summary>
    public ServerOptionValidator()
    {
        this.RuleFor(x => x.WebhookTolerance)
            .NotEmpty()
            .WithMessage("server_engine:webhook_tolerance must be an ISO 8601 duration")
            .Must(BeAWireDuration)
            .WithMessage("server_engine:webhook_tolerance must be an ISO 8601 duration such as PT5M")
            .Must(BeWithinEngineMaximum)
            .WithMessage(
                $"server_engine:webhook_tolerance must be positive and at most {WebhookConfig.MaximumTolerance}");

        // The engine refuses an empty key set at construction with an opaque
        // ArgumentException out of a library ctor. Failing HERE instead names the block and
        // the landscape that forgot to inject a key.
        this.RuleFor(x => x.WebhookSigningKeys)
            .NotEmpty()
            .WithMessage(
                "server_engine:webhook_signing_keys must list at least one key; " +
                "the webhook receiver cannot verify a signature without one");

        this.RuleForEach(x => x.WebhookSigningKeys)
            .NotEmpty()
            .WithMessage("server_engine:webhook_signing_keys entries must not be blank");
    }

    private static bool BeAWireDuration(string value) => Wire.ParseDuration(value).IsSuccess();

    private static bool BeWithinEngineMaximum(string value) => Wire
        .ParseDuration(value)
        .Match(
            duration => duration > TimeSpan.Zero && duration <= WebhookConfig.MaximumTolerance,
            _ => false);
}
