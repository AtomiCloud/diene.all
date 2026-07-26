namespace AtomiCloud.Diene.Otel;

/// <summary>
/// The service-tree identity this engine turns into resource attributes. Otel owns
/// its own identity input rather than depending on the config library: the config
/// library remains the sole merger and validator of the composed root, and this
/// engine only needs the five taxonomy values.
/// </summary>
/// <param name="Landscape">The deployment landscape, e.g. <c>lapras</c>.</param>
/// <param name="Platform">The platform the service belongs to.</param>
/// <param name="Service">The service name.</param>
/// <param name="Module">The module within the service.</param>
/// <param name="Version">The running version.</param>
public sealed record AppIdentity(
    string Landscape,
    string Platform,
    string Service,
    string Module,
    string Version)
{
    /// <summary>
    /// Validates and trims an identity. Every value is required and non-blank, so a
    /// half-configured service-tree block cannot silently produce anonymous
    /// telemetry.
    /// </summary>
    public static Result<AppIdentity, SeamError> Create(
        string? landscape,
        string? platform,
        string? service,
        string? module,
        string? version) =>
        Field("landscape", landscape)
            .Then(trimmedLandscape => Field("platform", platform)
                .Then(trimmedPlatform => Field("service", service)
                    .Then(trimmedService => Field("module", module)
                        .Then(trimmedModule => Field("version", version)
                            .Map(trimmedVersion => new AppIdentity(
                                trimmedLandscape,
                                trimmedPlatform,
                                trimmedService,
                                trimmedModule,
                                trimmedVersion))))));

    private static Result<string, SeamError> Field(string name, string? value) =>
        string.IsNullOrWhiteSpace(value)
            ? SeamErrors.InvalidArgument(SeamKind.Logging, name, $"The app identity '{name}' must not be blank.")
            : Result.Ok<string, SeamError>(value.Trim());
}
