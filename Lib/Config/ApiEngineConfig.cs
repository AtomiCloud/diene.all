using AtomiCloud.Diene.ApiEngine.Client;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.ApiEngine.Config;

/// <summary>
/// The validated <c>HttpClient</c> block: every upstream a service may call, keyed by its
/// LPSM address.
/// </summary>
/// <remarks>
/// Validation is total and returns a typed failure rather than throwing, so a service with
/// a mistyped upstream fails at composition with the offending field named, instead of at
/// the first call to it.
/// </remarks>
public sealed class ApiEngineConfig
{
    private readonly Dictionary<string, UpstreamConfig> _upstreams;

    private ApiEngineConfig(Dictionary<string, UpstreamConfig> upstreams) => _upstreams = upstreams;

    /// <summary>Gets every configured upstream, keyed by <c>platform.service.module</c>.</summary>
    public IReadOnlyDictionary<string, UpstreamConfig> Upstreams => _upstreams;

    /// <summary>
    /// Validates the whole block. Every key must be a well-formed service-tree address,
    /// because the key is what the client tree resolves a typed client by.
    /// </summary>
    public static Result<ApiEngineConfig, ApiConfigError> Create(
        IReadOnlyDictionary<string, HttpClientOption>? upstreams)
    {
        if (upstreams is null)
        {
            return new ApiConfigError(HttpClientOption.Key, "Upstream configuration is required.");
        }

        if (upstreams.Count == 0)
        {
            return new ApiConfigError(HttpClientOption.Key, "At least one upstream must be configured.");
        }

        var validated = new Dictionary<string, UpstreamConfig>(StringComparer.Ordinal);
        foreach (var (key, option) in upstreams)
        {
            var address = ServiceAddress.Parse(key);
            if (address.IsFailure(out var addressError))
            {
                return new ApiConfigError($"{HttpClientOption.Key}.{key}", addressError.Reason);
            }

            var canonical = address.Get().ToString();
            if (validated.ContainsKey(canonical))
            {
                return new ApiConfigError(
                    $"{HttpClientOption.Key}.{key}",
                    $"Upstream '{canonical}' is configured more than once.");
            }

            var upstream = UpstreamConfig.Create($"{HttpClientOption.Key}.{canonical}", option);
            if (upstream.IsFailure(out var upstreamError)) return upstreamError;

            validated[canonical] = upstream.Get();
        }

        return new ApiEngineConfig(validated);
    }

    /// <summary>Finds the configuration for one upstream.</summary>
    public Option<UpstreamConfig> Find(ServiceAddress address)
    {
        ArgumentNullException.ThrowIfNull(address);
        return _upstreams.TryGetValue(address.ToString(), out var upstream)
            ? Option.Some(upstream)
            : Option.None<UpstreamConfig>();
    }
}
