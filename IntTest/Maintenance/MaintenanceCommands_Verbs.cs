using AtomiCloud.DotnetBase.App.Maintenance;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.IntTest.Maintenance;

/// <summary>
/// The maintenance dispatcher and its READ-ONLY verbs, through their real implementations.
/// </summary>
/// <remarks>
/// <para>
/// <b>The write verbs are deliberately not exercised here.</b> <c>config:schema</c> and
/// <c>problems:export</c> resolve through <see cref="MaintenanceCommands.Absolute"/> to the REAL
/// repository root and write repository artifacts. A test that ran them would mutate the working
/// tree — and this tree is shared with other agents, so a test that dirties it can destroy work
/// that is not its own. The verify verbs assert the same artifacts without writing them.
/// </para>
/// <para>
/// <b>Every test here can fail for a reason that can be named.</b> Coverage rises when a line
/// executes, not when a test asserts something about it, so a test whose failure mode cannot be
/// stated is a line-toucher rather than a test. Each case below names its failure mode.
/// </para>
/// </remarks>
public class MaintenanceCommands_Verbs
{
    /// <summary>Fails if a verb is added or removed without the dispatcher set being updated.</summary>
    [Fact]
    public void It_should_declare_exactly_the_five_maintenance_verbs()
    {
        // Assert — on the VALUES, so a renamed constant fails rather than silently passing.
        MaintenanceCommands.Verbs.Should().BeEquivalentTo(
        [
            "config:schema",
            "config:schema:verify",
            "config:validate",
            "problems:export",
            "problems:verify",
        ]);
    }

    /// <summary>
    /// Fails if the dispatcher starts silently accepting an unknown verb — which would let a
    /// typo in CI exit 0 having done nothing at all.
    /// </summary>
    [Fact]
    public async Task It_should_refuse_a_verb_it_does_not_know()
    {
        // Act
        var refuse = async () => await MaintenanceCommands.RunAsync("config:schema:verifyy");

        // Assert
        await refuse.Should().ThrowAsync<ArgumentOutOfRangeException>();
    }

    /// <summary>
    /// Fails if repository-root resolution regresses. This encodes a REAL defect rather than a
    /// hypothetical: <c>dotnet run --project</c> sets the working directory to the PROJECT
    /// directory, so the relative path once resolved to <c>App/App/Config/settings.schema.json</c>
    /// and the command reported success while writing where nothing reads.
    /// </summary>
    [Fact]
    public void It_should_resolve_repository_paths_against_the_root_not_the_working_directory()
    {
        // Act
        var resolved = MaintenanceCommands.Absolute(MaintenanceCommands.SchemaPath);

        // Assert — the marker is beside the resolved path's root, and the relative segment
        // appears exactly ONCE. Doubling is the specific way this broke before.
        Path.IsPathRooted(resolved).Should().BeTrue();
        File.Exists(MaintenanceCommands.Absolute(MaintenanceCommands.RootMarker)).Should().BeTrue();
        var occurrences = resolved.Split("App/Config/settings.schema.json").Length - 1;
        occurrences.Should().Be(1, "the repository-relative segment must not be doubled");
        File.Exists(resolved).Should().BeTrue("the generated schema must exist at the resolved path");
    }

    /// <summary>
    /// Fails when the committed configuration schema has drifted from the options types — the
    /// drift this verb exists to catch.
    /// </summary>
    [Fact]
    public async Task It_should_report_the_configuration_schema_as_matching_the_options_types()
    {
        // Act
        var exit = await MaintenanceCommands.RunAsync(MaintenanceCommands.ConfigSchemaVerify);

        // Assert
        exit.Should().Be(MaintenanceCommands.Success, "committed settings.schema.json must match the options types");
    }

    /// <summary>
    /// Fails when the exported Problem catalog has drifted from the registered catalog, including
    /// a version whose file is missing and a file whose problem version no longer exists.
    /// </summary>
    [Fact]
    public async Task It_should_report_the_exported_problem_catalog_as_matching_the_registered_one()
    {
        // Act
        var exit = await MaintenanceCommands.RunAsync(MaintenanceCommands.ProblemsVerify);

        // Assert
        exit.Should().Be(MaintenanceCommands.Success, "exported catalog resources must match the registered catalog");
    }

    /// <summary>
    /// Fails when any configuration block is invalid on the FINAL merged layer — the same
    /// fail-fast <c>ValidateOnStart</c> performs at boot, checked without starting a web host.
    /// </summary>
    [Fact]
    public async Task It_should_validate_every_configuration_block_on_the_merged_layer()
    {
        // Act
        var exit = await MaintenanceCommands.RunAsync(MaintenanceCommands.ConfigValidate);

        // Assert
        exit.Should().Be(MaintenanceCommands.Success, "every registered configuration block must bind and validate");
    }
}
