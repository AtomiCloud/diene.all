using System.Reflection;
using System.Net;
using AtomiCloud.Diene.E2e.Drivers;
using AtomiCloud.Diene.E2e.TestHelper.Assertions;
using FluentAssertions;

namespace AtomiCloud.Diene.E2e.IntTest;

public class E2eDemo_Composition
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task It_should_drive_the_demo_through_the_inprocess_sit_path()
    {
        await using var driver = new InProcessSitDriver<global::Program>();

        using var response = await driver.Client.GetAsync("/system/health", Ct);

        response.ShouldHaveStatus(HttpStatusCode.OK);
        (await response.Content.ReadAsStringAsync(Ct)).Should().Contain("\"status\":\"ok\"");
    }

    [Fact]
    public void It_should_resolve_every_published_runtime_and_testhelper_assembly()
    {
        var names = PublishedPackageBundle.RuntimeAssemblyNames
            .Concat(PublishedPackageBundle.TestHelperAssemblyNames)
            .ToArray();

        var actual = names.Select(name => Assembly.Load(name).GetName().Name).ToArray();

        actual.Should().Equal(names);
    }
}
