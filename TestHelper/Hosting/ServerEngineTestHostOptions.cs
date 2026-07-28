using AtomiCloud.Diene.ServerEngine.Webhooks;
using Microsoft.Extensions.DependencyInjection;

namespace AtomiCloud.Diene.ServerEngine.TestHelper.Hosting;

/// <summary>What a test wants the in-process host to be.</summary>
public sealed class ServerEngineTestHostOptions
{
    /// <summary>Gets or sets the instant the host's clock reports.</summary>
    public DateTimeOffset Now { get; set; } = Builders.WebhookEnvelopeBuilder.DefaultReceivedAt;

    /// <summary>Gets or sets the accepted signature timestamp window.</summary>
    public TimeSpan Tolerance { get; set; } = Config.WebhookConfig.MaximumTolerance;

    /// <summary>Gets the signing keys the receiver verifies against. Empty is permitted.</summary>
    public IList<string> SigningKeys { get; } = [Builders.WebhookRequestSigner.DefaultKey];

    /// <summary>Gets the webhook handlers to register.</summary>
    public IList<IWebhookHandler> Handlers { get; } = [];

    /// <summary>
    /// Gets or sets whether the seven baseline problems are registered in the catalog.
    /// </summary>
    /// <remarks>
    /// Set it false to reach the unregistered-problem path for a problem that normally IS
    /// registered — which is what a consumer's own catalog mistake looks like from the outside.
    /// </remarks>
    public bool IncludeBaselineProblems { get; set; } = true;

    /// <summary>Gets or sets a hook for registering the consumer's own services.</summary>
    public Action<IServiceCollection>? Services { get; set; }
}
