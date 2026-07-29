using AtomiCloud.Diene.Problems.Catalog;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;

namespace AtomiCloud.Diene.Problems.App;

/// <summary>Builds the non-packable demo consumer and its registered problem boundary.</summary>
public static class ProblemApp
{
    /// <summary>Builds the demo app, with an optional host hook used by in-process integration tests.</summary>
    public static WebApplication Build(
        ProblemIdentity identity,
        ErrorPortalOption portal,
        Action<IWebHostBuilder>? configureWebHost = null)
    {
        var builder = WebApplication.CreateBuilder(new WebApplicationOptions
        {
            ApplicationName = typeof(ProblemApp).Assembly.FullName,
            Args = ["--hostBuilder:reloadConfigOnChange=false"],
        });
        configureWebHost?.Invoke(builder.WebHost);
        var registeredServices = builder.Services.AddAtomiProblems(
            identity,
            portal,
            catalog => catalog
                .AddBaseline()
                .Add<NoteMissing>(404, false, new ProblemEndpoint("GET", "/notes/{id}")));
        if (!ReferenceEquals(registeredServices, builder.Services))
            throw new InvalidOperationException("Problem registration must preserve the service collection.");

        var app = builder.Build();
        app.UseExceptionHandler();
        app.MapGet("/notes/{id}", ThrowNoteMissing);
        app.MapGet("/guard/{id}", GuardMissingEntity);
        app.MapGet("/unregistered", ThrowUnregistered);
        return app;
    }

    private static IResult ThrowNoteMissing(string id) => throw new NoteMissing(id).ToException();

    private static IResult GuardMissingEntity(string id) =>
        ProblemGuard.NotFound<string>(null, id).Match<IResult>(
            value => Microsoft.AspNetCore.Http.Results.Ok(value),
            problem => throw problem.ToException());

    private static IResult ThrowUnregistered() => throw new UnregisteredDemoProblem().ToException();
}
