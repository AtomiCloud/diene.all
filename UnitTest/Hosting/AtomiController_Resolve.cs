using System.Net;
using AtomiCloud.Diene.Problems.TestHelper;
using AtomiCloud.Diene.ServerEngine.Mvc;
using AtomiCloud.Diene.ServerEngine.TestHelper.Hosting;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Hosting;

public class AtomiController_Resolve
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task It_should_answer_200_with_the_value_on_success()
    {
        // Arrange
        await using var host = await ServerEngineTestHost.StartAsync();

        // Act
        var actual = await host.Client.GetAsync("/probe/value/known", Ct);

        // Assert
        actual.StatusCode.Should().Be(HttpStatusCode.OK);
        (await actual.Content.ReadAsStringAsync(Ct)).Should().Be("""{"value":"known"}""");
    }

    [Fact]
    public async Task It_should_answer_200_through_the_awaited_overload()
    {
        // Arrange
        await using var host = await ServerEngineTestHost.StartAsync();

        // Act
        var actual = await host.Client.GetAsync("/probe/value-async/known", Ct);

        // Assert
        actual.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task It_should_answer_204_when_a_unit_result_succeeds()
    {
        // Arrange
        await using var host = await ServerEngineTestHost.StartAsync();

        // Act
        var actual = await host.Client.DeleteAsync("/probe/value/known", Ct);

        // Assert
        actual.StatusCode.Should().Be(HttpStatusCode.NoContent);
        (await actual.Content.ReadAsStringAsync(Ct)).Should().BeEmpty();
    }

    [Fact]
    public async Task It_should_answer_204_through_the_awaited_unit_overload()
    {
        // Arrange
        await using var host = await ServerEngineTestHost.StartAsync();

        // Act
        var actual = await host.Client.DeleteAsync("/probe/value-async/known", Ct);

        // Assert
        actual.StatusCode.Should().Be(HttpStatusCode.NoContent);
    }

    [Fact]
    public async Task It_should_expose_a_correlation_identifier_per_request()
    {
        // Arrange
        await using var host = await ServerEngineTestHost.StartAsync();

        // Act
        var actual = await host.Client.GetStringAsync("/probe/trace", Ct);

        // Assert
        actual.Should().NotBe("""{"value":""}""").And.StartWith("""{"value":""");
    }

    [Theory]
    [ClassData(typeof(CatalogStatusCases))]
    public async Task It_should_render_a_typed_problem_at_its_catalog_status(string kind, int status)
    {
        // Arrange
        await using var host = await ServerEngineTestHost.StartAsync();

        // Act
        var actual = await host.Client.GetAsync($"/probe/problem/{kind}", Ct);

        // Assert
        ((int)actual.StatusCode).Should().Be(status);
        await actual.Should().BeRfc9457();
    }

    [Fact]
    public async Task It_should_render_a_failed_unit_result_through_the_same_filter()
    {
        // Arrange
        await using var host = await ServerEngineTestHost.StartAsync();

        // Act
        var actual = await host.Client.DeleteAsync("/probe/value/absent", Ct);

        // Assert
        actual.StatusCode.Should().Be(HttpStatusCode.NotFound);
        await actual.Should().BeRfc9457();
    }

    [Fact]
    public async Task It_should_render_a_failed_awaited_unit_result_through_the_same_filter()
    {
        // Arrange
        await using var host = await ServerEngineTestHost.StartAsync();

        // Act
        var actual = await host.Client.DeleteAsync("/probe/value-async/absent", Ct);

        // Assert
        actual.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task It_should_render_a_failed_awaited_value_result_through_the_same_filter()
    {
        // Arrange
        await using var host = await ServerEngineTestHost.StartAsync();

        // Act
        var actual = await host.Client.GetAsync("/probe/value-async/absent", Ct);

        // Assert
        actual.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task It_should_name_the_request_path_as_the_problem_instance()
    {
        // Arrange
        await using var host = await ServerEngineTestHost.StartAsync();

        // Act
        var response = await host.Client.GetAsync("/probe/value/absent", Ct);
        var actual = (await response.Should().BeRfc9457()).Which;

        // Assert
        actual.Instance.Should().Be("/probe/value/absent");
    }

    [Fact]
    public async Task It_should_answer_500_for_a_problem_the_catalog_does_not_know()
    {
        // Arrange
        await using var host = await ServerEngineTestHost.StartAsync();

        // Act
        var response = await host.Client.GetAsync("/probe/problem/unregistered", Ct);
        var actual = (await response.Should().BeRfc9457()).Which;

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.InternalServerError);
        actual.Type.Should().Be(ProblemEnvelope.UnregisteredType);
    }

    [Fact]
    public async Task It_should_answer_500_for_a_baseline_problem_when_the_catalog_is_empty()
    {
        // Arrange — this is what a consumer's own missing AddBaseline() looks like from outside.
        await using var host = await ServerEngineTestHost.StartAsync(
            options => options.IncludeBaselineProblems = false);

        // Act
        var actual = await host.Client.GetAsync("/probe/value/absent", Ct);

        // Assert
        actual.StatusCode.Should().Be(HttpStatusCode.InternalServerError);
    }

    [Fact]
    public async Task It_should_leave_an_exception_that_is_not_a_domain_problem_alone()
    {
        // Arrange — dressing a real defect up as a typed refusal would make the two
        // indistinguishable, so the filter must decline anything it was not built for.
        await using var host = await ServerEngineTestHost.StartAsync();

        // Act
        var act = async () => await host.Client.GetAsync("/probe/boom", Ct);

        // Assert
        await act.Should().ThrowAsync<InvalidOperationException>().WithMessage("probe boom");
    }

    private sealed class CatalogStatusCases : TheoryData<string, int>
    {
        public CatalogStatusCases()
        {
            this.Add("conflict", 409);
            this.Add("unauthenticated", 401);
            this.Add("other", 400);
        }
    }
}
