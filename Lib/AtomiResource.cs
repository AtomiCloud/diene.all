using OpenTelemetry.Resources;

namespace AtomiCloud.Diene.Otel;

/// <summary>
/// Maps the service-tree identity onto OpenTelemetry resource attributes. Resource
/// attributes are always derived, never hand-authored (C0 §4): each identity value
/// lands on its semantic-convention key AND on its raw <c>atomi.*</c> key, so
/// queries can use either vocabulary. <c>atomi.module</c> deliberately has no
/// semconv twin — the taxonomy is finer-grained than semconv.
/// </summary>
public static class AtomiResource
{
    /// <summary>The semconv key carrying the landscape.</summary>
    public const string DeploymentEnvironmentNameKey = "deployment.environment.name";

    /// <summary>The semconv key carrying the platform.</summary>
    public const string ServiceNamespaceKey = "service.namespace";

    /// <summary>The semconv key carrying the service.</summary>
    public const string ServiceNameKey = "service.name";

    /// <summary>The semconv key carrying the version.</summary>
    public const string ServiceVersionKey = "service.version";

    /// <summary>Maps the identity onto its resource attributes, block values only.</summary>
    public static IReadOnlyDictionary<string, string> Map(AppIdentity identity)
    {
        ArgumentNullException.ThrowIfNull(identity);
        return new SortedDictionary<string, string>(StringComparer.Ordinal)
        {
            [DeploymentEnvironmentNameKey] = identity.Landscape,
            [ServiceNamespaceKey] = identity.Platform,
            [ServiceNameKey] = identity.Service,
            [ServiceVersionKey] = identity.Version,
            ["atomi.landscape"] = identity.Landscape,
            ["atomi.module"] = identity.Module,
            ["atomi.platform"] = identity.Platform,
            ["atomi.service"] = identity.Service,
            ["atomi.version"] = identity.Version,
        };
    }

    /// <summary>
    /// Parses the <c>OTEL_RESOURCE_ATTRIBUTES</c> W3C-Baggage-style list. Entries
    /// without a key, or with an empty key, are dropped rather than rejected: the
    /// variable is an ops escape hatch and must never crash a service.
    /// </summary>
    public static IReadOnlyDictionary<string, string> ParseResourceAttributes(string? value)
    {
        var parsed = new SortedDictionary<string, string>(StringComparer.Ordinal);
        if (string.IsNullOrWhiteSpace(value)) return parsed;

        foreach (var entry in value.Split(','))
        {
            var trimmed = entry.Trim();
            if (trimmed.Length == 0) continue;

            var separator = trimmed.IndexOf('=', StringComparison.Ordinal);
            if (separator <= 0) continue;

            var key = trimmed[..separator].Trim();
            if (key.Length == 0) continue;

            parsed[key] = trimmed[(separator + 1)..].Trim();
        }

        return parsed;
    }

    /// <summary>
    /// The resource attributes a service actually reports: block-derived values
    /// first, then <c>OTEL_RESOURCE_ATTRIBUTES</c> and <c>OTEL_SERVICE_NAME</c>
    /// overriding them (C0 §4 escape hatch).
    /// </summary>
    public static IReadOnlyDictionary<string, string> Attributes(
        AppIdentity identity,
        IReadOnlyDictionary<string, string?> environment)
    {
        ArgumentNullException.ThrowIfNull(environment);

        var attributes = new SortedDictionary<string, string>(StringComparer.Ordinal);
        foreach (var (key, value) in Map(identity)) attributes[key] = value;

        environment.TryGetValue(OtelEnvironment.ResourceAttributesVariable, out var standard);
        foreach (var (key, value) in ParseResourceAttributes(standard)) attributes[key] = value;

        if (OtelEnvironment.HasValue(environment, OtelEnvironment.ServiceNameVariable))
        {
            attributes[ServiceNameKey] = environment[OtelEnvironment.ServiceNameVariable]!.Trim();
        }

        return attributes;
    }

    /// <summary>Builds the OpenTelemetry resource for the identity.</summary>
    public static ResourceBuilder Build(AppIdentity identity, IReadOnlyDictionary<string, string?> environment) =>
        ResourceBuilder
            .CreateEmpty()
            .AddAttributes(
                Attributes(identity, environment)
                    .Select(attribute => new KeyValuePair<string, object>(attribute.Key, attribute.Value)));
}
