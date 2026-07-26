using System.Text.Json;

namespace AtomiCloud.DotnetBase.UnitTest;

public class ConfigSchemaRegistryTests
{
    [Fact]
    public void A_registered_block_becomes_a_root_property()
    {
        var registry = new ConfigSchemaRegistry();
        registry.Register<PortalOption>(PortalOption.Key);

        using var document = JsonDocument.Parse(registry.ToJsonSchema());

        document.RootElement.GetProperty("properties").TryGetProperty(PortalOption.Key, out _)
            .Should().BeTrue();
    }

    [Fact]
    public void The_schema_permits_the_generated_pointer_C0_puts_on_the_first_line()
    {
        using var document = JsonDocument.Parse(new ConfigSchemaRegistry().ToJsonSchema());

        document.RootElement.GetProperty("properties").GetProperty("$schema").GetProperty("type")
            .GetString().Should().Be("string");
    }

    [Fact]
    public void A_service_composes_its_root_schema_from_several_engine_blocks()
    {
        var registry = new ConfigSchemaRegistry();
        registry.Register<AppOption>(AppOption.Key);
        registry.Register<PortalOption>(PortalOption.Key);

        registry.Blocks.Should().BeEquivalentTo(new Dictionary<string, Type>
        {
            [AppOption.Key] = typeof(AppOption),
            [PortalOption.Key] = typeof(PortalOption),
        });
    }

    [Fact]
    public void Registration_order_does_not_change_the_document()
    {
        var forward = new ConfigSchemaRegistry();
        forward.Register<AppOption>(AppOption.Key);
        forward.Register<PortalOption>(PortalOption.Key);

        var reverse = new ConfigSchemaRegistry();
        reverse.Register<PortalOption>(PortalOption.Key);
        reverse.Register<AppOption>(AppOption.Key);

        reverse.ToJsonSchema().Should().Be(forward.ToJsonSchema());
    }

    [Fact]
    public void Registering_the_same_key_twice_replaces_the_block()
    {
        var registry = new ConfigSchemaRegistry();
        registry.Register<AppOption>("Block");
        registry.Register<PortalOption>("Block");

        registry.Blocks["Block"].Should().Be<PortalOption>();
    }

    [Fact]
    public void Register_rejects_a_blank_key() =>
        FluentActions.Invoking(() => new ConfigSchemaRegistry().Register<AppOption>("  "))
            .Should().Throw<ArgumentException>();
}

public class ConfigSchemaGenTests : IDisposable
{
    private readonly string _directory = Directory.CreateTempSubdirectory("diene-config-schema").FullName;

    private static ConfigSchemaRegistry Registry()
    {
        var registry = new ConfigSchemaRegistry();
        registry.Register<AppOption>(AppOption.Key);
        return registry;
    }

    private string Path(string name) => System.IO.Path.Combine(_directory, name);

    [Fact]
    public void Writing_creates_the_directory_and_the_document()
    {
        var path = Path("generated/settings.schema.json");

        ConfigSchemaGen.WriteSchema(Registry(), path).IsSuccess().Should().BeTrue();

        File.ReadAllText(path).Should().Contain("\"App\"").And.EndWith("\n");
    }

    [Fact]
    public void Verifying_what_was_just_written_finds_no_drift()
    {
        var path = Path("settings.schema.json");
        ConfigSchemaGen.WriteSchema(Registry(), path);

        ConfigSchemaGen.VerifySchema(Registry(), path).IsSuccess().Should().BeTrue();
    }

    [Fact]
    public void Line_endings_are_a_checkout_artifact_not_drift()
    {
        var path = Path("settings.schema.json");
        ConfigSchemaGen.WriteSchema(Registry(), path);
        File.WriteAllText(path, File.ReadAllText(path).ReplaceLineEndings("\r\n"));

        ConfigSchemaGen.VerifySchema(Registry(), path).IsSuccess().Should().BeTrue();
    }

    [Fact]
    public void A_registry_that_gained_a_block_has_drifted_from_the_committed_file()
    {
        var path = Path("settings.schema.json");
        ConfigSchemaGen.WriteSchema(Registry(), path);

        var grown = Registry();
        grown.Register<PortalOption>(PortalOption.Key);

        var error = ConfigSchemaGen.VerifySchema(grown, path).GetFailure();

        error.Fault.Should().Be(SchemaGenFault.Drift);
        error.Path.Should().Be(path);
        error.Detail.Should().Contain("drifted");
    }

    [Fact]
    public void An_absent_schema_file_reports_missing_rather_than_drift()
    {
        var error = ConfigSchemaGen.VerifySchema(Registry(), Path("absent.json")).GetFailure();

        error.Fault.Should().Be(SchemaGenFault.Missing);
        error.Detail.Should().Contain("missing");
    }

    [Fact]
    public void An_unwritable_destination_reports_an_io_fault()
    {
        // Permission bits are the only portable way to make a write fail on demand.
        if (OperatingSystem.IsWindows()) return;

        var locked = Path("locked");
        Directory.CreateDirectory(locked);
        File.SetUnixFileMode(locked, UnixFileMode.UserRead | UnixFileMode.UserExecute);
        try
        {
            var error = ConfigSchemaGen.WriteSchema(Registry(), System.IO.Path.Combine(locked, "s.json"))
                .GetFailure();

            error.Fault.Should().Be(SchemaGenFault.Io);
            error.Detail.Should().NotBeEmpty();
        }
        finally
        {
            File.SetUnixFileMode(locked, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
        }
    }

    [Fact]
    public void An_unreadable_schema_file_reports_an_io_fault()
    {
        if (OperatingSystem.IsWindows()) return;

        var path = Path("unreadable.json");
        File.WriteAllText(path, "{}");
        File.SetUnixFileMode(path, UnixFileMode.None);
        try
        {
            ConfigSchemaGen.VerifySchema(Registry(), path).GetFailure().Fault.Should().Be(SchemaGenFault.Io);
        }
        finally
        {
            File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.UserWrite);
        }
    }

    [Fact]
    public void Writing_to_a_bare_file_name_needs_no_directory()
    {
        var name = $"schema-{Guid.NewGuid():N}.json";
        try
        {
            ConfigSchemaGen.WriteSchema(Registry(), name).IsSuccess().Should().BeTrue();
        }
        finally
        {
            File.Delete(name);
        }
    }

    [Fact]
    public void WriteSchema_rejects_a_null_registry() =>
        FluentActions.Invoking(() => ConfigSchemaGen.WriteSchema(null!, "s.json"))
            .Should().Throw<ArgumentNullException>();

    [Fact]
    public void WriteSchema_rejects_a_blank_path() =>
        FluentActions.Invoking(() => ConfigSchemaGen.WriteSchema(Registry(), "  "))
            .Should().Throw<ArgumentException>();

    [Fact]
    public void VerifySchema_rejects_a_null_registry() =>
        FluentActions.Invoking(() => ConfigSchemaGen.VerifySchema(null!, "s.json"))
            .Should().Throw<ArgumentNullException>();

    [Fact]
    public void VerifySchema_rejects_a_blank_path() =>
        FluentActions.Invoking(() => ConfigSchemaGen.VerifySchema(Registry(), "  "))
            .Should().Throw<ArgumentException>();

    public void Dispose()
    {
        Directory.Delete(_directory, recursive: true);
        GC.SuppressFinalize(this);
    }
}
