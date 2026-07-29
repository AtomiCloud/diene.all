using System.Text.Json;
using AtomiCloud.Diene.CoreUtils.Json;
using FluentAssertions;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.DependencyInjection;

namespace AtomiCloud.Diene.Problems.UnitTest;

public class DomainProblemExceptionHandler_TryHandleAsync
{
    private static readonly ProblemIdentity Identity = new("lapras", "dotnet", "notes", "api");
    private static readonly ErrorPortalOption Portal = new() { Scheme = "https", Host = "docs.example.test" };

    [Fact]
    public async Task It_should_render_registered_and_unknown_domain_problems_through_AddProblemDetails()
    {
        // Arrange
        using var provider = BuildProvider();
        var handler = provider.GetServices<IExceptionHandler>().OfType<DomainProblemExceptionHandler>().Single();
        var registeredContext = Context(provider, "/sample/one");
        var unknownContext = Context(provider, "/unknown");
        var cancellationToken = TestContext.Current.CancellationToken;

        // Act
        var registeredHandled = await handler.TryHandleAsync(
            registeredContext,
            new SampleProblem("one").ToException(),
            cancellationToken);
        var unknownHandled = await handler.TryHandleAsync(
            unknownContext,
            new OtherProblem().ToException(),
            cancellationToken);
        var registered = await ReadProblem(registeredContext);
        var unknown = await ReadProblem(unknownContext);

        // Assert
        registeredHandled.Should().BeTrue();
        registeredContext.Response.StatusCode.Should().Be(422);
        registeredContext.Response.ContentType.Should().StartWith("application/problem+json");
        registered.Type.Should().Be("https://docs.example.test/docs/lapras/dotnet/notes/api/v1/sample_problem");
        registered.Status.Should().Be(422);
        registered.Instance.Should().Be("/sample/one");
        registered.Recoverable.Should().BeTrue();
        registered.Data!["value"]!.GetValue<string>().Should().Be("one");
        registered.Extensions.Should().ContainKey("traceId");

        unknownHandled.Should().BeTrue();
        unknownContext.Response.StatusCode.Should().Be(500);
        unknown.Type.Should().Be("about:blank");
        unknown.Status.Should().Be(500);
        unknown.Recoverable.Should().BeFalse();
    }

    [Fact]
    public async Task It_should_decline_non_domain_exceptions_and_leave_generic_problem_details_untouched()
    {
        // Arrange
        using var provider = BuildProvider();
        var handler = provider.GetServices<IExceptionHandler>().OfType<DomainProblemExceptionHandler>().Single();
        var declinedContext = Context(provider, "/declined");
        var genericContext = Context(provider, "/generic");
        genericContext.Response.StatusCode = 400;
        var details = provider.GetRequiredService<IProblemDetailsService>();

        // Act
        var handled = await handler.TryHandleAsync(
            declinedContext,
            new InvalidOperationException("boom"),
            TestContext.Current.CancellationToken);
        await details.WriteAsync(new ProblemDetailsContext
        {
            HttpContext = genericContext,
            ProblemDetails = new ProblemDetails { Status = 400, Title = "Generic" },
        });
        var generic = await ReadProblem(genericContext);

        // Assert
        handled.Should().BeFalse();
        declinedContext.Response.Body.Length.Should().Be(0);
        generic.Status.Should().Be(400);
        generic.Title.Should().Be("Generic");
    }

    [Fact]
    public void It_should_register_the_catalog_exporter_emitter_and_validate_inputs()
    {
        // Arrange
        var services = new ServiceCollection();
        services.AddLogging();

        // Act
        var actual = services.AddAtomiProblems(Identity, Portal, catalog => catalog.Add<SampleProblem>(422, true));
        using var provider = services.BuildServiceProvider();

        // Assert
        actual.Should().BeSameAs(services);
        provider.GetRequiredService<ErrorPortalConfig>().Identity.Should().Be(Identity);
        provider.GetRequiredService<IProblemTypeUriBuilder>().Should().BeOfType<ProblemTypeUriBuilder>();
        provider.GetRequiredService<ProblemCatalog>().All.Should().ContainSingle();
        provider.GetRequiredService<IProblemCatalog>().Should().BeSameAs(provider.GetRequiredService<ProblemCatalog>());
        provider.GetRequiredService<IProblemExporter>().Should().BeOfType<ProblemExporter>();
        provider.GetRequiredService<ProblemResourceEmitter>().Should().NotBeNull();
    }

    [Fact]
    public void It_should_reject_null_registration_and_handler_dependencies()
    {
        // Arrange
        var services = new ServiceCollection();
        services.AddLogging();
        using var provider = BuildProvider();
        var details = provider.GetRequiredService<IProblemDetailsService>();
        var catalog = provider.GetRequiredService<IProblemCatalog>();

        // Act
        var nullServices = () => ProblemsServiceCollectionExtensions.AddAtomiProblems(null!, Identity, Portal, _ => { });
        var nullIdentity = () => services.AddAtomiProblems(null!, Portal, _ => { });
        var nullPortal = () => services.AddAtomiProblems(Identity, null!, _ => { });
        var nullCatalog = () => services.AddAtomiProblems(Identity, Portal, null!);
        var invalidPortal = () => services.AddAtomiProblems(
            Identity,
            new ErrorPortalOption { Scheme = "https", Host = "bad/path" },
            _ => { });
        var nullDetails = () => new DomainProblemExceptionHandler(null!, catalog);
        var nullHandlerCatalog = () => new DomainProblemExceptionHandler(details, null!);

        // Assert
        nullServices.Should().Throw<ArgumentNullException>();
        nullIdentity.Should().Throw<ArgumentNullException>();
        nullPortal.Should().Throw<ArgumentNullException>();
        nullCatalog.Should().Throw<ArgumentNullException>();
        invalidPortal.Should().Throw<ArgumentOutOfRangeException>();
        nullDetails.Should().Throw<ArgumentNullException>();
        nullHandlerCatalog.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public async Task It_should_reject_a_null_HTTP_context()
    {
        // Arrange
        using var provider = BuildProvider();
        var handler = provider.GetServices<IExceptionHandler>().OfType<DomainProblemExceptionHandler>().Single();

        // Act
        var act = async () => await handler.TryHandleAsync(
            null!,
            new Exception(),
            TestContext.Current.CancellationToken);

        // Assert
        await act.Should().ThrowAsync<ArgumentNullException>();
    }

    private static ServiceProvider BuildProvider()
    {
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddAtomiProblems(Identity, Portal, catalog => catalog.Add<SampleProblem>(422, true));
        return services.BuildServiceProvider();
    }

    private static DefaultHttpContext Context(IServiceProvider services, string path)
    {
        var context = new DefaultHttpContext { RequestServices = services };
        context.Request.Path = path;
        context.Response.Body = new MemoryStream();
        return context;
    }

    private static async Task<Problem> ReadProblem(DefaultHttpContext context)
    {
        context.Response.Body.Position = 0;
        return (await JsonSerializer.DeserializeAsync<Problem>(
            context.Response.Body,
            AtomiJson.DefaultOptions,
            TestContext.Current.CancellationToken))!;
    }
}
