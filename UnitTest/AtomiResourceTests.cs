namespace AtomiCloud.DotnetBase.UnitTest;

public class AtomiResourceTests
{
    private static AppIdentity Identity { get; } = new("lapras", "atomi", "billing", "api", "1.2.3");

    [Theory]
    [InlineData("deployment.environment.name", "lapras")]
    [InlineData("service.namespace", "atomi")]
    [InlineData("service.name", "billing")]
    [InlineData("service.version", "1.2.3")]
    [InlineData("atomi.landscape", "lapras")]
    [InlineData("atomi.platform", "atomi")]
    [InlineData("atomi.service", "billing")]
    [InlineData("atomi.module", "api")]
    [InlineData("atomi.version", "1.2.3")]
    public void Map_LandsEveryIdentityValueOnItsKey(string key, string expected) =>
        AtomiResource.Map(Identity)[key].Should().Be(expected);

    [Fact]
    public void Map_ShipsNineKeysAndNoSemconvTwinForModule()
    {
        var mapped = AtomiResource.Map(Identity);
        mapped.Should().HaveCount(9);
        mapped.Keys.Should().NotContain("service.module");
    }

    [Fact]
    public void Map_RejectsANullIdentity() =>
        FluentActions.Invoking(() => AtomiResource.Map(null!)).Should().Throw<ArgumentNullException>();

    [Fact]
    public void SemconvKeys_AreTheSpecSpellings()
    {
        AtomiResource.DeploymentEnvironmentNameKey.Should().Be("deployment.environment.name");
        AtomiResource.ServiceNamespaceKey.Should().Be("service.namespace");
        AtomiResource.ServiceNameKey.Should().Be("service.name");
        AtomiResource.ServiceVersionKey.Should().Be("service.version");
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void ParseResourceAttributes_TreatsAnAbsentValueAsEmpty(string? value) =>
        AtomiResource.ParseResourceAttributes(value).Should().BeEmpty();

    [Fact]
    public void ParseResourceAttributes_ReadsABaggageStyleList()
    {
        var parsed = AtomiResource.ParseResourceAttributes(" tenant = acme , region=ap-southeast-1 ");
        parsed.Should().HaveCount(2);
        parsed["tenant"].Should().Be("acme");
        parsed["region"].Should().Be("ap-southeast-1");
    }

    [Theory]
    [InlineData("malformed")]
    [InlineData("=orphan")]
    [InlineData(" =orphan")]
    [InlineData(",,")]
    public void ParseResourceAttributes_DropsUnusableEntriesRatherThanFailing(string value) =>
        AtomiResource.ParseResourceAttributes(value).Should().BeEmpty();

    [Fact]
    public void ParseResourceAttributes_KeepsAnEmptyValueForAKnownKey() =>
        AtomiResource.ParseResourceAttributes("tenant=")["tenant"].Should().BeEmpty();

    [Fact]
    public void ParseResourceAttributes_KeepsAValueContainingAnEqualsSign() =>
        AtomiResource.ParseResourceAttributes("filter=a=b")["filter"].Should().Be("a=b");

    [Fact]
    public void Attributes_UsesTheBlockWhenNoEnvironmentOverridesExist() =>
        AtomiResource
            .Attributes(Identity, Env.None)
            .Should().BeEquivalentTo(AtomiResource.Map(Identity));

    [Fact]
    public void Attributes_LetsResourceAttributesOverrideABlockDerivedValue() =>
        AtomiResource
            .Attributes(
                Identity,
                Env.Of((OtelEnvironment.ResourceAttributesVariable, "service.name=override,tenant=acme")))
            .Should().Contain(new KeyValuePair<string, string>("service.name", "override"))
            .And.Contain(new KeyValuePair<string, string>("tenant", "acme"));

    [Fact]
    public void Attributes_LetsServiceNameWinOverResourceAttributes() =>
        AtomiResource
            .Attributes(
                Identity,
                Env.Of(
                    (OtelEnvironment.ResourceAttributesVariable, "service.name=from-list"),
                    (OtelEnvironment.ServiceNameVariable, " from-variable ")))[AtomiResource.ServiceNameKey]
            .Should().Be("from-variable");

    [Fact]
    public void Attributes_IgnoresABlankServiceNameOverride() =>
        AtomiResource
            .Attributes(Identity, Env.Of((OtelEnvironment.ServiceNameVariable, "  ")))[AtomiResource.ServiceNameKey]
            .Should().Be("billing");

    [Fact]
    public void Attributes_RejectsANullEnvironment() =>
        FluentActions.Invoking(() => AtomiResource.Attributes(Identity, null!))
            .Should().Throw<ArgumentNullException>();

    [Fact]
    public void Build_ProducesAResourceCarryingTheMappedAttributes()
    {
        var resource = AtomiResource.Build(Identity, Env.None).Build();
        resource.Attributes.Should().Contain(new KeyValuePair<string, object>("service.name", "billing"));
        resource.Attributes.Should().Contain(new KeyValuePair<string, object>("atomi.module", "api"));
        resource.Attributes.Should().HaveCount(9);
    }
}
