namespace AtomiCloud.DotnetBase.MetaTest;

/// <summary>
/// Assert-the-asserter for the one gate that enforces the R14 UPPERCASE contract.
/// </summary>
public class PresetYamlAuditTests
{
    private const string Good = """
        $schema: ./schema.json
        postgres:
          MAIN:
            host: localhost
          READ_REPLICA:
            host: replica
        cache:
          MAIN:
            host: localhost
        """;

    private const string Bad = """
        postgres:
          main:
            host: localhost
        storage:
          Main:
            bucket: app
        """;

    private static IReadOnlyList<PresetKeyViolation> Audit(string yaml, string label = "settings.yaml") =>
        PresetYamlAudit.Audit(label, new StringReader(yaml));

    [Fact]
    public void It_should_find_nothing_in_uppercase_yaml() => Audit(Good).Should().BeEmpty();

    [Fact]
    public void It_should_report_every_lowercase_and_mixed_case_name()
    {
        var violations = Audit(Bad);

        violations.Should().HaveCount(2);
        violations.Select(violation => violation.Name).Should().BeEquivalentTo(["main", "Main"]);
        violations.Should().AllSatisfy(violation => violation.File.Should().Be("settings.yaml"));
    }

    [Fact]
    public void It_should_name_the_block_the_violation_is_in() =>
        Audit(Bad).Should().Contain(violation => violation.Block == "storage" && violation.Name == "Main");

    [Fact]
    public void It_should_render_a_violation_readably() =>
        new PresetKeyViolation("settings.yaml", "postgres", "main")
            .ToString()
            .Should()
            .Be("settings.yaml: postgres.main is not UPPERCASE");

    [Fact]
    public void It_should_recognise_a_block_authored_in_another_casing() =>
        Audit("Postgres:\n  main:\n    host: x\n").Should().ContainSingle();

    [Fact]
    public void It_should_ignore_keys_that_are_not_preset_blocks() =>
        Audit("app:\n  landscape: lapras\nerror_portal:\n  host: x\n").Should().BeEmpty();

    [Fact]
    public void It_should_ignore_a_preset_block_that_is_not_a_mapping() =>
        Audit("postgres: ~\n").Should().BeEmpty();

    [Fact]
    public void It_should_ignore_a_non_scalar_connection_name() =>
        Audit("postgres:\n  ? [a, b]\n  : host: x\n").Should().BeEmpty();

    [Fact]
    public void It_should_ignore_a_non_scalar_block_name() =>
        Audit("? [a, b]\n: host: x\n").Should().BeEmpty();

    [Fact]
    public void It_should_treat_an_empty_document_as_clean() => Audit("").Should().BeEmpty();

    [Fact]
    public void It_should_treat_a_comment_only_document_as_clean() => Audit("# nothing here\n").Should().BeEmpty();

    [Fact]
    public void It_should_treat_a_non_mapping_document_as_clean() => Audit("- one\n- two\n").Should().BeEmpty();

    [Fact]
    public void It_should_reject_a_blank_label()
    {
        var audit = () => PresetYamlAudit.Audit("  ", new StringReader(Good));
        audit.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void It_should_reject_a_null_reader()
    {
        var audit = () => PresetYamlAudit.Audit("settings.yaml", null!);
        audit.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_list_the_four_frozen_block_names() =>
        PresetYamlAudit.BlockNames.Should().BeEquivalentTo(["Postgres", "Cache", "Kv", "Storage"]);

    // ── the file and directory entry points ─────────────────────────────────────────────

    [Fact]
    public void It_should_audit_a_file_on_disk()
    {
        using var scratch = new Scratch(("settings.yaml", Good));

        PresetYamlAudit.Audit(scratch.Path("settings.yaml")).Should().BeEmpty();
    }

    [Fact]
    public void It_should_reject_a_blank_path()
    {
        var audit = () => PresetYamlAudit.Audit("  ");
        audit.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void It_should_pass_a_clean_file()
    {
        using var scratch = new Scratch(("settings.yaml", Good));

        var assert = () => PresetYamlAudit.ShouldUseUppercaseConnectionNames(scratch.Path("settings.yaml"));
        assert.Should().NotThrow();
    }

    [Fact]
    public void It_should_fail_a_dirty_file()
    {
        using var scratch = new Scratch(("settings.yaml", Bad));

        var assert = () => PresetYamlAudit.ShouldUseUppercaseConnectionNames(scratch.Path("settings.yaml"));
        assert.Should().Throw<Exception>().WithMessage("*UPPERCASE*");
    }

    [Fact]
    public void It_should_pass_a_clean_directory()
    {
        using var scratch = new Scratch(("settings.yaml", Good), ("settings.lapras.yaml", "kv:\n  MAIN:\n    db: 1\n"));

        var assert = () => PresetYamlAudit.ShouldUseUppercaseConnectionNames(scratch.Directory, "settings*.yaml");
        assert.Should().NotThrow();
    }

    [Fact]
    public void It_should_fail_a_directory_whose_overlay_drifted()
    {
        using var scratch = new Scratch(("settings.yaml", Good), ("settings.lapras.yaml", "kv:\n  main:\n    db: 1\n"));

        var assert = () => PresetYamlAudit.ShouldUseUppercaseConnectionNames(scratch.Directory, "settings*.yaml");
        assert.Should().Throw<Exception>().WithMessage("*main*");
    }

    [Fact]
    public void It_should_reject_a_blank_directory()
    {
        var audit = () => PresetYamlAudit.ShouldUseUppercaseConnectionNames("  ", "*.yaml");
        audit.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void It_should_reject_a_blank_search_pattern()
    {
        using var scratch = new Scratch(("settings.yaml", Good));

        var audit = () => PresetYamlAudit.ShouldUseUppercaseConnectionNames(scratch.Directory, "  ");
        audit.Should().Throw<ArgumentException>();
    }

    private sealed class Scratch : IDisposable
    {
        internal Scratch(params (string Name, string Content)[] files)
        {
            Directory = System.IO.Directory.CreateTempSubdirectory("preset-yaml-audit").FullName;
            foreach (var (name, content) in files) File.WriteAllText(Path(name), content);
        }

        internal string Directory { get; }

        internal string Path(string name) => System.IO.Path.Combine(Directory, name);

        public void Dispose() => System.IO.Directory.Delete(Directory, recursive: true);
    }
}
