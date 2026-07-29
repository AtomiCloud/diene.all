using System.Net;
using System.Net.Http.Json;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Problems.Catalog;
using AtomiCloud.Diene.Problems.TestHelper;
using AtomiCloud.DotnetBase.App.Modules.Info;
using AtomiCloud.Diene.ServerEngine.Mvc;
using AtomiCloud.DotnetBase.IntTest.Api.Doubles;
using AtomiCloud.DotnetBase.Lib.Note;
using FluentAssertions;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;

namespace AtomiCloud.DotnetBase.IntTest.Api;

/// <summary>
/// The error contract on the wire: one envelope, RFC 9457, for every tier of failure. The point of
/// the tiers is that they must NOT be distinguishable by shape — a caller parses one contract, and
/// the only things that vary are the status and the type URI.
/// </summary>
public class NoteProblem_Envelope : IAsyncLifetime
{
    private readonly ServiceHost _host = new();

    public ValueTask InitializeAsync() => ValueTask.CompletedTask;

    public async ValueTask DisposeAsync() => await this._host.DisposeAsync();

    [Fact]
    public async Task It_should_render_a_registered_problem_with_a_versioned_type_uri_and_its_data()
    {
        // Arrange — the domain answers the PORTABLE conflict; the API boundary is what restates it
        // as this service's documented note_title_conflict.
        using var factory = this.With(new EntityConflict("taken", typeof(NotePrincipal)));
        var client = factory.CreateClient();

        // The single source of the type URI is the builder. Formatting the ErrorPortal template
        // here would make this test agree with itself rather than with the service.
        var expected = factory.Services
            .GetRequiredService<IProblemTypeUriBuilder>()
            .Build("v1", "note_title_conflict")
            .ToString();

        // Act
        var response = await client.PostAsJsonAsync(
            "/api/v1/notes",
            new { title = "Taken", body = "second" },
            TestContext.Current.CancellationToken);

        // Assert
        var problem = (await response.Should().BeRfc9457()).Which;
        problem.Should().HaveStatus((int)HttpStatusCode.Conflict);
        problem.Should().HaveType(expected);
        problem.Should().HaveData(new NoteTitleConflictData("Taken"));
        response.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task It_should_render_the_not_found_tier_as_the_same_envelope()
    {
        // Arrange
        using var factory = this.With(new EntityNotFound("gone", typeof(NotePrincipal), "absent"));
        var client = factory.CreateClient();

        // Act
        var response = await client.GetAsync("/api/v1/notes/absent", TestContext.Current.CancellationToken);

        // Assert
        var problem = (await response.Should().BeRfc9457()).Which;
        problem.Should().HaveStatus((int)HttpStatusCode.NotFound);
        problem.Type.Should().NotBe(ProblemEnvelope.UnregisteredType);
    }

    [Fact]
    public async Task It_should_render_a_malformed_body_as_rfc_9457_rather_than_the_framework_shape()
    {
        // Arrange — no [ApiController], so there is no automatic 400 in ASP.NET's own shape. This
        // is the test that would catch someone adding it: the second contract would show up here.
        using var factory = this.With(new EntityNotFound("unused", typeof(NotePrincipal), "unused"));
        var client = factory.CreateClient();

        // Act — a body with no title at all
        var response = await client.PostAsJsonAsync(
            "/api/v1/notes",
            new { body = "no title" },
            TestContext.Current.CancellationToken);

        // Assert
        var problem = (await response.Should().BeRfc9457()).Which;
        problem.Status.Should().BeGreaterThanOrEqualTo(400).And.BeLessThan(500);
        problem.Detail.Should().NotBeNullOrWhiteSpace();
    }

    [Fact]
    public async Task It_should_render_a_typed_but_unregistered_problem_as_500_about_blank()
    {
        // Arrange — a problem no catalog holds is a CATALOG DEFECT. The library's answer is 500
        // with about:blank, and pinning that is the point: inventing a friendlier status here
        // would hide a real registration mistake in a service that ships.
        using var factory = this.With(new UnregisteredProblem());
        var client = factory.CreateClient();

        // Act
        var response = await client.GetAsync("/api/v1/notes/anything", TestContext.Current.CancellationToken);

        // Assert
        var problem = (await response.Should().BeRfc9457()).Which;
        problem.Should().HaveStatus((int)HttpStatusCode.InternalServerError);
        problem.Should().HaveType(ProblemEnvelope.UnregisteredType);
    }

    [Fact]
    public async Task It_should_render_a_raw_exception_as_the_same_envelope()
    {
        // Arrange — an exception that is not a problem at all must still leave as RFC 9457, which
        // is what UseExceptionHandler plus the shipped filter are for.
        using var factory = this.Throwing(new InvalidOperationException("the store fell over"));
        var client = factory.CreateClient();

        // Act
        var response = await client.GetAsync("/api/v1/notes/anything", TestContext.Current.CancellationToken);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.InternalServerError);
        var problem = (await response.Should().BeRfc9457()).Which;
        problem.Should().HaveStatus((int)HttpStatusCode.InternalServerError);

        // The message must NOT reach the caller: an internal failure is not a disclosure channel.
        problem.Detail.Should().NotContain("the store fell over");
    }

    private WebApplicationFactory<InfoController> Throwing(Exception failure) =>
        this.Substitute(new StubNotes(null, failure));

    private WebApplicationFactory<InfoController> With(IDomainProblem problem) =>
        this.Substitute(new StubNotes(problem));

    private WebApplicationFactory<InfoController> Substitute(INotes stub) => this._host
        .WithWebHostBuilder(builder => builder
            .ConfigureTestServices(services => services.AddScoped(_ => stub)));

    /// <summary>The typed payload NoteTitleConflict puts under the envelope data extension.</summary>
    /// <param name="RequestedTitle">The title that collided.</param>
    private sealed record NoteTitleConflictData(string RequestedTitle);
}
