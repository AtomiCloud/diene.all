using Asp.Versioning;
using AtomiCloud.Diene.CoreUtils.Json;
using AtomiCloud.DotnetBase.App.Options;
using FluentValidation;
using Microsoft.AspNetCore.HttpOverrides;
using Scalar.AspNetCore;

namespace AtomiCloud.DotnetBase.App.StartUp.Registration;

/// <summary>Versioning, MVC, validation, CORS, and OpenAPI layers of the composition root.</summary>
public static class ControllerRegistration
{
    /// <summary>Name of the single configured CORS policy.</summary>
    public const string CorsPolicy = "service";

    /// <summary>Registers API versioning with attribute routing.</summary>
    /// <param name="services">The service collection to extend.</param>
    /// <returns>The same collection.</returns>
    public static IServiceCollection AddServiceVersioning(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services
            .AddApiVersioning(versioning =>
            {
                versioning.DefaultApiVersion = new ApiVersion(1, 0);
                versioning.AssumeDefaultVersionWhenUnspecified = true;
                versioning.ReportApiVersions = true;
                versioning.ApiVersionReader = new UrlSegmentApiVersionReader();
            })
            .AddMvc()
            .AddApiExplorer(explorer =>
            {
                explorer.GroupNameFormat = "'v'VVV";
                explorer.SubstituteApiVersionInUrl = true;
            });

        return services;
    }

    /// <summary>
    /// Registers full MVC controllers. This assembly is added as its own application part:
    /// the server engine adds its own, and under a test host the entry assembly is the test
    /// project, so an unregistered part means every route here 404s with nothing reporting why.
    /// </summary>
    /// <param name="services">The service collection to extend.</param>
    /// <param name="http">The bound <c>http:</c> block.</param>
    /// <returns>The same collection.</returns>
    public static IServiceCollection AddServiceControllers(this IServiceCollection services, HttpOption http)
    {
        ArgumentNullException.ThrowIfNull(services);
        ArgumentNullException.ThrowIfNull(http);

        // No [ApiController]: it installs an automatic 400 in ASP.NET's own shape, which would
        // put a second error contract on the wire beside RFC 9457.
        services
            .AddControllers()
            .AddApplicationPart(typeof(ControllerRegistration).Assembly)
            .AddJsonOptions(options => AtomiJson.Apply(options.JsonSerializerOptions));

        services.AddValidatorsFromAssembly(typeof(ControllerRegistration).Assembly, includeInternalTypes: false);

        if (http.Cors.Enabled)
        {
            services.AddCors(cors => cors.AddPolicy(CorsPolicy, policy =>
            {
                policy
                    .WithOrigins([.. http.Cors.AllowedOrigins])
                    .WithMethods([.. http.Cors.AllowedMethods])
                    .WithHeaders([.. http.Cors.AllowedHeaders]);

                if (http.Cors.AllowCredentials) policy.AllowCredentials();
            }));
        }

        if (http.ForwardedHeaders)
        {
            services.Configure<ForwardedHeadersOptions>(options =>
                options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto);
        }

        if (http.OpenApi.Enabled) services.AddOpenApi();

        return services;
    }

    /// <summary>Mounts the OpenAPI document and, when configured, the reference UI.</summary>
    /// <param name="application">The application to extend.</param>
    /// <param name="http">The bound <c>http:</c> block.</param>
    /// <returns>The same application.</returns>
    public static WebApplication UseServiceOpenApi(this WebApplication application, HttpOption http)
    {
        ArgumentNullException.ThrowIfNull(application);
        ArgumentNullException.ThrowIfNull(http);

        if (!http.OpenApi.Enabled) return application;

        application.MapOpenApi();
        if (http.OpenApi.Ui) application.MapScalarApiReference();

        return application;
    }
}
