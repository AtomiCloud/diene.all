using System.Diagnostics.CodeAnalysis;
using System.Text.RegularExpressions;

namespace AtomiCloud.Diene.ServerEngine.Webhooks;

/// <summary>
/// Resolves the handler for a provider, and refuses an ambiguous or malformed registration at
/// composition rather than at delivery time.
/// </summary>
/// <remarks>
/// Two handlers registered for one provider is a programming error with a silent failure mode:
/// whichever the container happened to enumerate first would win, so half the events would be
/// processed by the wrong code and nothing would report it. Throwing here turns that into a
/// startup failure the deployment sees.
/// </remarks>
public sealed partial class WebhookHandlerRegistry
{
    private readonly Dictionary<string, IWebhookHandler> _handlers;

    /// <summary>Builds the registry over every registered handler.</summary>
    public WebhookHandlerRegistry(IEnumerable<IWebhookHandler> handlers)
    {
        ArgumentNullException.ThrowIfNull(handlers);

        this._handlers = new Dictionary<string, IWebhookHandler>(StringComparer.OrdinalIgnoreCase);
        foreach (var handler in handlers)
        {
            var provider = handler.Provider;
            if (string.IsNullOrWhiteSpace(provider) || !ProviderPattern().IsMatch(provider))
            {
                throw new InvalidOperationException(
                    $"Webhook handler {handler.GetType().FullName} declares provider '{provider}', which is not a lowercase provider id.");
            }

            if (!this._handlers.TryAdd(provider, handler))
            {
                throw new InvalidOperationException($"Webhook provider '{provider}' has more than one handler.");
            }
        }
    }

    /// <summary>Gets every registered provider id.</summary>
    public IReadOnlyCollection<string> Providers => this._handlers.Keys;

    /// <summary>
    /// Finds the handler for a provider. An absent provider is a normal answer — the receiver
    /// reports it as "not mine", never as an error.
    /// </summary>
    public bool TryResolve(string provider, [NotNullWhen(true)] out IWebhookHandler? handler)
    {
        if (string.IsNullOrWhiteSpace(provider))
        {
            handler = null;
            return false;
        }

        return this._handlers.TryGetValue(provider, out handler);
    }

    [GeneratedRegex("^[a-z0-9][a-z0-9._-]*$", RegexOptions.CultureInvariant)]
    private static partial Regex ProviderPattern();
}
