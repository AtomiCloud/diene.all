using Microsoft.Extensions.Configuration;

namespace AtomiCloud.DotnetBase.UnitTest;

public class EnvLayerTests
{
    private static IConfiguration Load(params (string Name, string? Value)[] variables) =>
        new ConfigurationBuilder()
            .AddAtomiEnvironmentVariables(
                "ATOMI_",
                variables.Select(v => new KeyValuePair<string, string?>(v.Name, v.Value)))
            .Build();

    [Fact]
    public void Double_underscore_is_the_nesting_separator() =>
        Load(("ATOMI_ERROR_PORTAL__HOST", "alpha"))["errorportal:host"].Should().Be("alpha");

    [Fact]
    public void Deep_nesting_keeps_going() =>
        Load(("ATOMI_A__B__C__D", "deep"))["a:b:c:d"].Should().Be("deep");

    [Fact]
    public void List_elements_arrive_as_indexed_keys_not_as_JSON_or_commas()
    {
        var config = Load(("ATOMI_HOSTS__0", "alpha"), ("ATOMI_HOSTS__1", "beta"));

        config.GetSection("hosts").GetChildren().Select(child => child.Value)
            .Should().Equal("alpha", "beta");
    }

    [Theory]
    [InlineData("ATOMI_ERROR_PORTAL__HOST")]
    [InlineData("ATOMI_error-portal__host")]
    [InlineData("ATOMI_errorPortal__Host")]
    public void Every_spelling_of_a_name_lands_on_the_same_key(string name) =>
        Load((name, "alpha"))["errorportal:host"].Should().Be("alpha");

    [Fact]
    public void The_prefix_itself_matches_case_insensitively() =>
        Load(("atomi_host", "alpha"))["host"].Should().Be("alpha");

    [Fact]
    public void A_variable_without_the_prefix_is_not_ours() =>
        Load(("OTHER_HOST", "alpha")).AsEnumerable().Should().BeEmpty();

    [Fact]
    public void The_bare_prefix_is_not_a_key() =>
        Load(("ATOMI_", "alpha")).AsEnumerable().Should().BeEmpty();

    [Fact]
    public void A_name_with_an_empty_nesting_segment_is_not_a_key() =>
        Load(("ATOMI_A__", "alpha")).AsEnumerable().Should().BeEmpty();

    [Fact]
    public void A_variable_may_carry_a_null_value() =>
        Load(("ATOMI_HOST", null))["host"].Should().BeNull();

    [Fact]
    public void The_process_environment_overload_reads_real_variables()
    {
        const string name = "ATOMI_UNITTEST_PROCESS_PROBE__VALUE";
        Environment.SetEnvironmentVariable(name, "from-process");
        try
        {
            new ConfigurationBuilder().AddAtomiEnvironmentVariables("ATOMI_UNITTEST_PROCESS_PROBE__").Build()["value"]
                .Should().Be("from-process");
        }
        finally
        {
            Environment.SetEnvironmentVariable(name, null);
        }
    }

    [Fact]
    public void AddAtomiEnvironmentVariables_rejects_a_null_builder() =>
        FluentActions.Invoking(() => ((IConfigurationBuilder)null!).AddAtomiEnvironmentVariables("ATOMI_", []))
            .Should().Throw<ArgumentNullException>();

    [Fact]
    public void AddAtomiEnvironmentVariables_rejects_a_blank_prefix() =>
        FluentActions.Invoking(() => new ConfigurationBuilder().AddAtomiEnvironmentVariables("  ", []))
            .Should().Throw<ArgumentException>();

    [Fact]
    public void AddAtomiEnvironmentVariables_rejects_null_variables() =>
        FluentActions.Invoking(() => new ConfigurationBuilder().AddAtomiEnvironmentVariables("ATOMI_", null!))
            .Should().Throw<ArgumentNullException>();
}
