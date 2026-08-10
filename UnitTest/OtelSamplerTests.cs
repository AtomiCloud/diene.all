namespace AtomiCloud.DotnetBase.UnitTest;

public class OtelSamplerTests
{
    [Fact]
    public void Names_AreTheCanonicalSamplerTypes()
    {
        OtelSampler.ParentBasedTraceIdRatio.Should().Be("parentbased_traceidratio");
        OtelSampler.AlwaysOn.Should().Be("always_on");
        OtelSampler.AlwaysOff.Should().Be("always_off");
    }

    [Fact]
    public void Create_MapsAlwaysOn() =>
        OtelSampler
            .Create(new SamplerOption { Type = OtelSampler.AlwaysOn }, Env.None)
            .Should().BeOk()
            .Which.Should().BeSome()
            .Which.Description.Should().Be("AlwaysOnSampler");

    [Fact]
    public void Create_MapsAlwaysOff() =>
        OtelSampler
            .Create(new SamplerOption { Type = OtelSampler.AlwaysOff }, Env.None)
            .Should().BeOk()
            .Which.Should().BeSome()
            .Which.Description.Should().Be("AlwaysOffSampler");

    [Theory]
    [InlineData(0.0)]
    [InlineData(0.25)]
    [InlineData(1.0)]
    public void Create_WrapsARatioSamplerInAParentBasedDecision(double ratio) =>
        OtelSampler
            .Create(new SamplerOption { Type = OtelSampler.ParentBasedTraceIdRatio, Ratio = ratio }, Env.None)
            .Should().BeOk()
            .Which.Should().BeSome()
            .Which.Description.Should().StartWith("ParentBased{TraceIdRatioBasedSampler{");

    [Theory]
    [InlineData(-0.1)]
    [InlineData(1.1)]
    [InlineData(double.NaN)]
    public void Create_RejectsARatioOutsideTheUnitInterval(double ratio) =>
        OtelSampler
            .Create(new SamplerOption { Type = OtelSampler.ParentBasedTraceIdRatio, Ratio = ratio }, Env.None)
            .Should().BeErr()
            .Which.Message.Should().Contain("between 0 and 1");

    [Theory]
    [InlineData("traceidratio")]
    [InlineData("coin_flip")]
    [InlineData("")]
    public void Create_RejectsAnUnsupportedType(string type) =>
        OtelSampler
            .Create(new SamplerOption { Type = type }, Env.None)
            .Should().BeErr()
            .Which.Message.Should().Contain("not a supported sampler type");

    [Fact]
    public void Create_DefersToTheSdkWhenTheEnvironmentNamesASampler() =>
        OtelSampler
            .Create(
                new SamplerOption { Type = OtelSampler.AlwaysOn },
                Env.Of((OtelEnvironment.TracesSamplerVariable, "always_off")))
            .Should().BeOk()
            .Which.Should().BeNone();

    [Fact]
    public void Create_IgnoresABlankSamplerOverride() =>
        OtelSampler
            .Create(
                new SamplerOption { Type = OtelSampler.AlwaysOn },
                Env.Of((OtelEnvironment.TracesSamplerVariable, "  ")))
            .Should().BeOk()
            .Which.Should().BeSome();

    [Fact]
    public void Create_ReportsAnUnsupportedTypeAsASamplerFailure() =>
        OtelSampler
            .Create(new SamplerOption { Type = "nope" }, Env.None)
            .Should().BeErr()
            .Which.Operation.Should().Be("sampler");

    [Fact]
    public void Create_RejectsNullArguments()
    {
        FluentActions.Invoking(() => OtelSampler.Create(null!, Env.None)).Should().Throw<ArgumentNullException>();
        FluentActions.Invoking(() => OtelSampler.Create(new SamplerOption(), null!))
            .Should().Throw<ArgumentNullException>();
    }
}

public class InstrumentationTests
{
    private static AppIdentity Identity { get; } = new("lapras", "atomi", "billing", "api", "1.2.3");

    [Fact]
    public void Construct_NamesBothSourcesFromTheIdentity()
    {
        using var instrumentation = new Instrumentation(Identity);

        instrumentation.Identity.Should().Be(Identity);
        instrumentation.ActivitySource.Name.Should().Be("billing");
        instrumentation.ActivitySource.Version.Should().Be("1.2.3");
        instrumentation.Meter.Name.Should().Be("billing");
        instrumentation.Meter.Version.Should().Be("1.2.3");
    }

    [Fact]
    public void Construct_RejectsANullIdentity() =>
        FluentActions.Invoking(() => new Instrumentation(null!)).Should().Throw<ArgumentNullException>();

    [Fact]
    public void Dispose_IsIdempotent()
    {
        var instrumentation = new Instrumentation(Identity);
        instrumentation.Dispose();
        FluentActions.Invoking(instrumentation.Dispose).Should().NotThrow();
    }
}

public class OtelBlockSchemaTests
{
    [Fact]
    public void ResourceName_IsTheEmbeddedLogicalName() =>
        OtelBlockSchema.ResourceName.Should().Be("AtomiCloud.Diene.Otel.otel-block.schema.json");

    [Fact]
    public void Json_IsTheEngineOwnedBlockSchema()
    {
        OtelBlockSchema.Json.Should().Contain("\"$schema\"");
        OtelBlockSchema.Json.Should().Contain("parentbased_traceidratio");
        OtelBlockSchema.Json.Should().Contain("http/protobuf");
    }

    [Fact]
    public void Json_IsLoadedOnceAndCached() =>
        OtelBlockSchema.Json.Should().BeSameAs(OtelBlockSchema.Json);
}
