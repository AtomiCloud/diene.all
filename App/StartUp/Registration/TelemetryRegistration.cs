using AtomiCloud.Diene.Config;
using AtomiCloud.Diene.Otel;

namespace AtomiCloud.DotnetBase.App.StartUp.Registration;

/// <summary>Logging and OpenTelemetry layers of the composition root.</summary>
public static class TelemetryRegistration
{
    /// <summary>
    /// Configures host logging. The structured sinks the application code writes through come
    /// from the otel engine's <c>ILoggerSink</c>; this only shapes the host's own output.
    /// </summary>
    /// <param name="builder">The host builder to extend.</param>
    /// <returns>The same builder.</returns>
    public static WebApplicationBuilder AddServiceLogging(this WebApplicationBuilder builder)
    {
        ArgumentNullException.ThrowIfNull(builder);

        builder.Logging.ClearProviders();
        builder.Logging.AddSimpleConsole(console =>
        {
            console.SingleLine = true;
            console.TimestampFormat = "yyyy-MM-ddTHH:mm:ss.fffZ ";
            console.UseUtcTimestamp = true;
        });

        return builder;
    }

    /// <summary>
    /// Wires all three signals from the canonical <c>otel:</c> block. Resource attributes are
    /// DERIVED from service-tree identity, never hand-authored, and every exporter ships off
    /// until a landscape overlay turns one on.
    /// </summary>
    /// <param name="builder">The host builder to extend.</param>
    /// <param name="app">The bound service-tree identity.</param>
    /// <returns>The same builder.</returns>
    public static WebApplicationBuilder AddServiceTelemetry(this WebApplicationBuilder builder, AppOption app)
    {
        ArgumentNullException.ThrowIfNull(builder);
        ArgumentNullException.ThrowIfNull(app);

        var identity = AppIdentity
            .Create(app.Landscape, app.Platform, app.Service, app.Module, app.Version)
            .Match(
                value => value,
                error => throw new InvalidOperationException(
                    $"configuration block 'app' cannot form a service identity: {error}"));

        // A malformed otel block is a value, not an exception thrown out of the startup path.
        // This service decides deliberately that it should stop the process: half-wired
        // telemetry is worse than none, because it looks configured.
        builder
            .AddAtomiOtel(identity, builder.Configuration, OtelEnvironment.Process())
            .Match(
                _ => { },
                error => throw new InvalidOperationException(
                    $"configuration block 'otel' is invalid: {error}"));

        return builder;
    }
}
