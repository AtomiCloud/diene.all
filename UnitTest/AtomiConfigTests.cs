using Microsoft.Extensions.Configuration;

namespace AtomiCloud.DotnetBase.UnitTest;

/// <summary>
/// The C0 §3 precedence contract: base → sparse landscape overlay → prefixed environment LAST.
/// </summary>
/// <remarks>
/// Every test that touches the LANDSCAPE variable lives in this one class, because xUnit
/// parallelises across classes but not within one and the variable is process-global.
/// </remarks>
public class AtomiConfigTests : IDisposable
{
    private readonly string _directory = Directory.CreateTempSubdirectory("diene-config-layers").FullName;

    private AtomiConfigSource Source(string landscape = "lapras") => new()
    {
        BaseFile = Path.Combine(_directory, "settings.yaml"),
        LandscapePattern = Path.Combine(_directory, "settings.{0}.yaml"),
        Landscape = landscape,
        EnvPrefix = "ATOMI_",
    };

    private void WriteBase(string yaml) => File.WriteAllText(Path.Combine(_directory, "settings.yaml"), yaml);

    private void WriteOverlay(string landscape, string yaml) =>
        File.WriteAllText(Path.Combine(_directory, $"settings.{landscape}.yaml"), yaml);

    private static IConfiguration Build(AtomiConfigSource source, params (string, string?)[] environment)
    {
        foreach (var (name, value) in environment) Environment.SetEnvironmentVariable(name, value);
        try
        {
            return new ConfigurationBuilder().AddAtomiConfig(source).Build();
        }
        finally
        {
            foreach (var (name, _) in environment) Environment.SetEnvironmentVariable(name, null);
        }
    }

    [Fact]
    public void The_base_layer_supplies_defaults()
    {
        WriteBase("error_portal:\n  scheme: https\n  host: base\n");

        Build(Source())["errorportal:scheme"].Should().Be("https");
    }

    [Fact]
    public void A_sparse_landscape_overlay_beats_the_base_layer_key_by_key()
    {
        WriteBase("error_portal:\n  scheme: https\n  host: base\n");
        WriteOverlay("lapras", "error_portal:\n  host: overlay\n");

        var config = Build(Source());

        config["errorportal:host"].Should().Be("overlay");
        config["errorportal:scheme"].Should().Be("https", "the overlay is sparse and says nothing about the scheme");
    }

    [Fact]
    public void The_environment_layer_beats_both_files()
    {
        WriteBase("error_portal:\n  host: base\n");
        WriteOverlay("lapras", "error_portal:\n  host: overlay\n");

        Build(Source(), ("ATOMI_ERROR_PORTAL__HOST", "environment"))["errorportal:host"]
            .Should().Be("environment");
    }

    [Fact]
    public void A_secret_declared_blank_in_yaml_is_filled_by_the_environment()
    {
        WriteBase("error_portal:\n  signing_key:\n");

        Build(Source(), ("ATOMI_ERROR_PORTAL__SIGNING_KEY", "injected"))["errorportal:signingkey"]
            .Should().Be("injected");
    }

    [Fact]
    public void An_absent_landscape_overlay_is_optional()
    {
        WriteBase("host: base\n");

        Build(Source("no-such-landscape"))["host"].Should().Be("base");
    }

    [Fact]
    public void A_missing_base_layer_is_fatal_because_it_carries_the_defaults() =>
        FluentActions.Invoking(() => Build(Source())).Should().Throw<FileNotFoundException>();

    [Fact]
    public void A_blank_landscape_is_resolved_from_the_LANDSCAPE_variable()
    {
        WriteBase("host: base\n");
        WriteOverlay("mareep", "host: from-mareep\n");

        Environment.SetEnvironmentVariable(AtomiConfigSource.LandscapeVariable, "mareep");
        try
        {
            Build(Source(landscape: ""))["host"].Should().Be("from-mareep");
        }
        finally
        {
            Environment.SetEnvironmentVariable(AtomiConfigSource.LandscapeVariable, null);
        }
    }

    [Fact]
    public void No_landscape_anywhere_means_no_overlay_layer_at_all()
    {
        WriteBase("host: base\n");
        WriteOverlay("mareep", "host: from-mareep\n");

        Environment.SetEnvironmentVariable(AtomiConfigSource.LandscapeVariable, null);

        Build(Source(landscape: "  "))["host"].Should().Be("base");
    }

    [Fact]
    public void EnvPrefix_is_required_because_the_library_bakes_no_default()
    {
        WriteBase("host: base\n");

        FluentActions.Invoking(() => Build(Source() with { EnvPrefix = "  " }))
            .Should().Throw<ArgumentException>().WithMessage("*EnvPrefix is required*");
    }

    [Fact]
    public void Reload_on_change_is_refused_rather_than_silently_ignored()
    {
        WriteBase("host: base\n");

        FluentActions.Invoking(() => Build(Source() with { ReloadOnChange = true }))
            .Should().Throw<ArgumentException>().WithMessage("*not supported in v1*");
    }

    [Fact]
    public void AddAtomiConfig_rejects_a_null_builder() =>
        FluentActions.Invoking(() => ((IConfigurationBuilder)null!).AddAtomiConfig(Source()))
            .Should().Throw<ArgumentNullException>();

    [Fact]
    public void AddAtomiConfig_rejects_a_null_source() =>
        FluentActions.Invoking(() => new ConfigurationBuilder().AddAtomiConfig(null!))
            .Should().Throw<ArgumentNullException>();

    [Fact]
    public void The_source_defaults_point_at_the_conventional_config_directory()
    {
        var source = new AtomiConfigSource { EnvPrefix = "ATOMI_" };

        source.BaseFile.Should().Be("Config/settings.yaml");
        source.LandscapePattern.Should().Be("Config/settings.{0}.yaml");
        source.Landscape.Should().BeEmpty();
        source.ReloadOnChange.Should().BeFalse();
        AtomiConfigSource.LandscapeVariable.Should().Be("LANDSCAPE");
    }

    public void Dispose()
    {
        Directory.Delete(_directory, recursive: true);
        GC.SuppressFinalize(this);
    }
}
