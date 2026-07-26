using System.Diagnostics;
using System.Text.Json;
using AtomiCloud.Diene.CoreUtils.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace AtomiCloud.Diene.Problems;

/// <summary>Registers the typed problem catalog, exporter, and modern ASP.NET Core adapter.</summary>
public static class ProblemsServiceCollectionExtensions
{
    /// <summary>Registers consumer-owned problem types and their ASP.NET Core rendering pipeline.</summary>
    public static IServiceCollection AddAtomiProblems(
        this IServiceCollection services,
        ProblemIdentity identity,
        ErrorPortalOption portal,
        Action<ProblemCatalogBuilder> catalog)
    {
        ArgumentNullException.ThrowIfNull(services);
        ArgumentNullException.ThrowIfNull(identity);
        ArgumentNullException.ThrowIfNull(portal);
        ArgumentNullException.ThrowIfNull(catalog);

        var portalConfig = new ErrorPortalConfig(portal.Scheme, portal.Host, identity);
        var typeUris = new ProblemTypeUriBuilder(portalConfig);
        var catalogBuilder = new ProblemCatalogBuilder();
        catalog(catalogBuilder);

        services.AddSingleton(portalConfig);
        services.AddSingleton<IProblemTypeUriBuilder>(typeUris);
        services.AddSingleton(serviceProvider =>
            catalogBuilder.Build(serviceProvider.GetRequiredService<ILogger<ProblemCatalog>>()));
        services.AddSingleton<IProblemCatalog>(serviceProvider => serviceProvider.GetRequiredService<ProblemCatalog>());
        services.AddSingleton<IProblemExporter, ProblemExporter>();
        services.AddSingleton<ProblemResourceEmitter>();
        services.AddProblemDetails(options => options.CustomizeProblemDetails = CustomizeProblemDetails);
        services.AddExceptionHandler<DomainProblemExceptionHandler>();
        return services;
    }

    private static void CustomizeProblemDetails(ProblemDetailsContext context)
    {
        if (!context.HttpContext.Items.TryGetValue(ProblemHttpContext.DomainProblemKey, out var candidate) ||
            candidate is not IDomainProblem problem)
        {
            return;
        }

        var services = context.HttpContext.RequestServices;
        var catalog = services.GetRequiredService<IProblemCatalog>();
        var typeUris = services.GetRequiredService<IProblemTypeUriBuilder>();
        var descriptor = catalog.Find(problem.Version, problem.Id);
        var registered = descriptor.IsSome() && descriptor.Get().Type == problem.GetType();

        context.ProblemDetails.Type = BuildTypeUri(typeUris, problem, registered);
        context.ProblemDetails.Title = problem.Title;
        context.ProblemDetails.Status = context.HttpContext.Response.StatusCode;
        context.ProblemDetails.Detail = problem.Detail;
        context.ProblemDetails.Instance ??= context.HttpContext.Request.Path;
        context.ProblemDetails.Extensions["data"] = JsonSerializer.SerializeToNode(
            problem,
            problem.GetType(),
            AtomiJson.DefaultOptions);
        context.ProblemDetails.Extensions["recoverable"] = registered && descriptor.Get().Recoverable;
        context.ProblemDetails.Extensions.TryAdd(
            "traceId",
            Activity.Current?.Id ?? context.HttpContext.TraceIdentifier);
    }

    private static string BuildTypeUri(
        IProblemTypeUriBuilder typeUris,
        IDomainProblem problem,
        bool registered)
    {
        if (!registered) return "about:blank";
        return typeUris.Build(problem.Version, problem.Id).AbsoluteUri;
    }
}
