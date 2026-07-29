using AtomiCloud.Diene.E2e.Drivers;
using FluentAssertions;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;

namespace AtomiCloud.Diene.E2e.UnitTest.Drivers;

public class InProcessSitDriver_Construct
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task It_should_drive_the_real_application_pipeline()
    {
        await using var subject = new InProcessSitDriver<global::Program>();

        var response = await subject.Client.GetAsync("/system/health", Ct);

        response.EnsureSuccessStatusCode();
        (await response.Content.ReadAsStringAsync(Ct)).Should().Contain("\"status\":\"ok\"");
        subject.Services.Should().NotBeNull();
    }

    [Fact]
    public async Task It_should_accept_a_configured_factory()
    {
        using var factory = new WebApplicationFactory<global::Program>()
            .WithWebHostBuilder(builder => builder.UseSetting("environment", "Testing"));
        await using var subject = new InProcessSitDriver<global::Program>(factory);

        var response = await subject.Client.GetAsync("/system/health", Ct);

        response.EnsureSuccessStatusCode();
    }
}
