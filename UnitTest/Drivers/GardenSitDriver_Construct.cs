using AtomiCloud.Diene.E2e.Drivers;
using AtomiCloud.Diene.E2e.Garden;
using FluentAssertions;

namespace AtomiCloud.Diene.E2e.UnitTest.Drivers;

public class GardenSitDriver_Construct
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task It_should_create_a_client_for_the_endpoint()
    {
        await using var subject = new GardenSitDriver(new Uri("https://service.test.invalid/path"));

        subject.Client.BaseAddress.Should().Be(new Uri("https://service.test.invalid/path"));
    }

    [Fact]
    public async Task It_should_accept_a_caller_owned_handler()
    {
        using var handler = new StubHandler();
        await using var subject = new GardenSitDriver(new Uri("http://service.test.invalid"), handler);

        var actual = await subject.Client.GetAsync("/", Ct);

        actual.StatusCode.Should().Be(System.Net.HttpStatusCode.NoContent);
    }

    [Theory]
    [InlineData("relative")]
    [InlineData("ftp://service.test.invalid")]
    public void It_should_refuse_a_non_http_endpoint(string value)
    {
        var endpoint = new Uri(value, UriKind.RelativeOrAbsolute);

        var act = () => new GardenSitDriver(endpoint);

        act.Should().Throw<E2eHarnessException>();
    }

    [Fact]
    public void It_should_refuse_a_null_endpoint()
    {
        var act = () => new GardenSitDriver(null!);

        act.Should().Throw<ArgumentNullException>();
    }

    private sealed class StubHandler : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            _ = request;
            _ = cancellationToken;
            return Task.FromResult(new HttpResponseMessage(System.Net.HttpStatusCode.NoContent));
        }
    }
}
