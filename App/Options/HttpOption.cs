using FluentValidation;

namespace AtomiCloud.DotnetBase.App.Options;

/// <summary>
/// The <c>http:</c> block: everything about how this service is exposed. CORS origins, the
/// OpenAPI branding, and the forwarded-headers posture are configuration rather than code so
/// the rebrand gate has nothing hardcoded to find (R21).
/// </summary>
public sealed class HttpOption
{
    /// <summary>Configuration key this block binds to.</summary>
    public const string Key = "Http";

    /// <summary>Cross-origin settings.</summary>
    public CorsOption Cors { get; set; } = new();

    /// <summary>OpenAPI document branding.</summary>
    public OpenApiOption OpenApi { get; set; } = new();

    /// <summary>
    /// Whether to honour X-Forwarded-* headers. On in every landscape that sits behind a
    /// gateway; off locally, where trusting them would let a client forge its own scheme.
    /// </summary>
    public bool ForwardedHeaders { get; set; }
}

/// <summary>Cross-origin resource sharing settings.</summary>
public sealed class CorsOption
{
    /// <summary>Whether the CORS middleware is wired at all.</summary>
    public bool Enabled { get; set; }

    /// <summary>Exact allowed origins. Wildcards are refused; name the origins.</summary>
    public IList<string> AllowedOrigins { get; set; } = [];

    /// <summary>Allowed methods.</summary>
    public IList<string> AllowedMethods { get; set; } = ["GET", "POST", "PUT", "DELETE", "OPTIONS"];

    /// <summary>Allowed request headers.</summary>
    public IList<string> AllowedHeaders { get; set; } = ["Authorization", "Content-Type"];

    /// <summary>Whether credentials may cross the origin boundary.</summary>
    public bool AllowCredentials { get; set; }
}

/// <summary>OpenAPI document branding, kept out of the source so a rebrand is a values change.</summary>
public sealed class OpenApiOption
{
    /// <summary>Whether the OpenAPI document and its UI are served.</summary>
    public bool Enabled { get; set; } = true;

    /// <summary>Document title.</summary>
    public string Title { get; set; } = string.Empty;

    /// <summary>Document description.</summary>
    public string Description { get; set; } = string.Empty;

    /// <summary>Whether the Scalar reference UI is mounted alongside the document.</summary>
    public bool Ui { get; set; }
}

/// <summary>Validates <see cref="HttpOption"/> on the final merged configuration layer.</summary>
public sealed class HttpOptionValidator : AbstractValidator<HttpOption>
{
    /// <summary>Declares the block's rules.</summary>
    public HttpOptionValidator()
    {
        this.When(x => x.Cors.Enabled, () =>
        {
            this.RuleFor(x => x.Cors.AllowedOrigins)
                .NotEmpty()
                .WithMessage("http:cors:allowed_origins must name at least one origin when CORS is enabled");

            this.RuleForEach(x => x.Cors.AllowedOrigins)
                .Must(origin => origin != "*")
                .WithMessage("http:cors:allowed_origins must not contain a wildcard; name the origins")
                .Must(origin => Uri.TryCreate(origin, UriKind.Absolute, out _))
                .WithMessage("http:cors:allowed_origins entries must be absolute origins");

            this.RuleFor(x => x.Cors.AllowedMethods).NotEmpty();
        });

        this.RuleFor(x => x.Cors)
            .Must(cors => !cors.AllowCredentials || cors.AllowedOrigins.All(origin => origin != "*"))
            .WithMessage("http:cors:allow_credentials cannot be combined with a wildcard origin");

        this.When(x => x.OpenApi.Enabled, () =>
        {
            this.RuleFor(x => x.OpenApi.Title)
                .NotEmpty()
                .WithMessage("http:open_api:title is required; the service must not hardcode its own branding");
        });
    }
}
