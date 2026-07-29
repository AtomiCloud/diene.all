using FluentAssertions;

namespace AtomiCloud.Diene.E2e.UnitTest;

public class PublishedPackageBundle_Inventory
{
    [Fact]
    public void It_should_name_all_ten_runtime_packages()
    {
        PublishedPackageBundle.RuntimeAssemblyNames.Should().HaveCount(10)
            .And.Contain("AtomiCloud.Diene.ApiEngine")
            .And.Contain("AtomiCloud.Diene.ServerEngine");
    }

    [Fact]
    public void It_should_bundle_only_the_nine_real_test_helpers()
    {
        PublishedPackageBundle.TestHelperAssemblyNames.Should().HaveCount(9)
            .And.NotContain("AtomiCloud.Diene.CoreUtils.TestHelper")
            .And.Contain("AtomiCloud.Diene.ServerEngine.TestHelper");
    }
}
