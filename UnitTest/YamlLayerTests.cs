using Microsoft.Extensions.Configuration;

namespace AtomiCloud.DotnetBase.UnitTest;

public class YamlLayerTests : IDisposable
{
    private readonly string _directory = Directory.CreateTempSubdirectory("diene-config-yaml").FullName;

    private IConfiguration Load(string yaml, [System.Runtime.CompilerServices.CallerMemberName] string name = "")
    {
        var path = Path.Combine(_directory, name + ".yaml");
        File.WriteAllText(path, yaml);
        return new ConfigurationBuilder().AddAtomiYamlFile(path, optional: false).Build();
    }

    [Fact]
    public void Nested_mappings_flatten_onto_canonical_colon_delimited_keys()
    {
        var config = Load("""
            error_portal:
              retry_policy:
                max-attempts: 3
            """);

        config["errorportal:retrypolicy:maxattempts"].Should().Be("3");
    }

    [Fact]
    public void Sequences_become_indexed_keys_so_the_binder_sees_a_collection()
    {
        var config = Load("""
            hosts:
              - alpha
              - beta
            """);

        config.GetSection("hosts").GetChildren().Select(child => child.Value)
            .Should().Equal("alpha", "beta");
    }

    [Fact]
    public void Nested_objects_inside_a_sequence_keep_their_index()
    {
        var config = Load("""
            backends:
              - name: alpha
              - name: beta
            """);

        config["backends:1:name"].Should().Be("beta");
    }

    [Fact]
    public void A_blank_scalar_declares_the_key_without_a_value()
    {
        var config = Load("""
            error_portal:
              signing_key:
            """);

        config.AsEnumerable().Select(pair => pair.Key).Should().Contain("errorportal:signingkey");
        config["errorportal:signingkey"].Should().BeEmpty("the key is declared so the environment layer can fill it");
    }

    [Fact]
    public void The_generated_schema_pointer_is_not_a_config_key()
    {
        var config = Load("""
            $schema: ./settings.schema.json
            host: alpha
            """);

        config.AsEnumerable().Select(pair => pair.Key).Should().NotContain("$schema");
        config["host"].Should().Be("alpha");
    }

    [Fact]
    public void A_nested_schema_key_is_ordinary_config_because_only_the_root_pointer_is_special()
    {
        var config = Load("""
            block:
              $schema: kept
            """);

        config["block:$schema"].Should().Be("kept");
    }

    [Fact]
    public void An_empty_file_is_a_legal_empty_layer() =>
        Load("").AsEnumerable().Should().BeEmpty();

    [Fact]
    public void A_comments_only_file_is_a_legal_empty_layer() =>
        Load("# nothing to declare yet\n").AsEnumerable().Should().BeEmpty();

    [Fact]
    public void A_layer_whose_root_is_not_a_mapping_is_rejected() =>
        FluentActions.Invoking(() => Load("- alpha\n- beta\n"))
            .Should().Throw<InvalidDataException>()
            .WithInnerException<InvalidDataException>()
            .WithMessage("*must be a YAML mapping at its root*");

    [Fact]
    public void A_non_scalar_config_key_is_rejected() =>
        FluentActions.Invoking(() => Load("? [alpha, beta]\n: value\n"))
            .Should().Throw<InvalidDataException>()
            .WithInnerException<InvalidDataException>()
            .WithMessage("*Config keys must be YAML scalars*");

    [Fact]
    public void A_non_scalar_key_nested_inside_a_block_is_rejected() =>
        FluentActions.Invoking(() => Load("block:\n  ? [alpha]\n  : value\n"))
            .Should().Throw<InvalidDataException>()
            .WithInnerException<InvalidDataException>()
            .WithMessage("*Config keys must be YAML scalars*");

    [Fact]
    public void A_missing_required_layer_fails_loudly() =>
        FluentActions.Invoking(() => new ConfigurationBuilder()
                .AddAtomiYamlFile(Path.Combine(_directory, "absent.yaml"), optional: false)
                .Build())
            .Should().Throw<FileNotFoundException>();

    [Fact]
    public void A_missing_optional_layer_contributes_nothing() =>
        new ConfigurationBuilder()
            .AddAtomiYamlFile(Path.Combine(_directory, "absent.yaml"), optional: true)
            .Build()
            .AsEnumerable().Should().BeEmpty();

    [Fact]
    public void A_relative_layer_path_resolves_against_the_working_directory()
    {
        var name = $"relative-{Guid.NewGuid():N}.yaml";
        File.WriteAllText(Path.Combine(Directory.GetCurrentDirectory(), name), "host: alpha\n");
        try
        {
            new ConfigurationBuilder().AddAtomiYamlFile(name, optional: false).Build()["host"]
                .Should().Be("alpha");
        }
        finally
        {
            File.Delete(Path.Combine(Directory.GetCurrentDirectory(), name));
        }
    }

    [Fact]
    public void AddAtomiYamlFile_rejects_a_null_builder() =>
        FluentActions.Invoking(() => ((IConfigurationBuilder)null!).AddAtomiYamlFile("a.yaml", optional: true))
            .Should().Throw<ArgumentNullException>();

    [Fact]
    public void AddAtomiYamlFile_rejects_a_blank_path() =>
        FluentActions.Invoking(() => new ConfigurationBuilder().AddAtomiYamlFile("  ", optional: true))
            .Should().Throw<ArgumentException>();

    public void Dispose()
    {
        Directory.Delete(_directory, recursive: true);
        GC.SuppressFinalize(this);
    }
}
