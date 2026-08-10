using System.Diagnostics;
using System.Diagnostics.Metrics;

namespace AtomiCloud.Diene.Otel;

/// <summary>
/// The app-scoped <see cref="System.Diagnostics.ActivitySource" /> and
/// <see cref="System.Diagnostics.Metrics.Meter" /> every seam implementation emits
/// through. Both are named from the service identity, so a span or instrument is
/// attributable to a service and version without reading its resource.
/// </summary>
public sealed class Instrumentation : IDisposable
{
    /// <summary>Builds the instrumentation for a service identity.</summary>
    /// <param name="identity">The service identity that names both sources.</param>
    public Instrumentation(AppIdentity identity)
    {
        ArgumentNullException.ThrowIfNull(identity);
        Identity = identity;
        ActivitySource = new ActivitySource(identity.Service, identity.Version);
        Meter = new Meter(identity.Service, identity.Version);
    }

    /// <summary>The identity that named the sources.</summary>
    public AppIdentity Identity { get; }

    /// <summary>The span source. Its name is the activity-source name traces subscribe to.</summary>
    public ActivitySource ActivitySource { get; }

    /// <summary>The instrument factory. Its name is the meter name metrics subscribe to.</summary>
    public Meter Meter { get; }

    /// <inheritdoc />
    public void Dispose()
    {
        ActivitySource.Dispose();
        Meter.Dispose();
    }
}
