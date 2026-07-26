using System.Text.Json.Nodes;
using FluentAssertions;

namespace AtomiCloud.Diene.Problems.UnitTest;

public class ProblemExporter_Export
{
    private static readonly ProblemIdentity Identity = new("lapras", "dotnet", "notes", "api");
    private static readonly ErrorPortalConfig Portal = new("https", "docs.example.test", Identity);

    [Fact]
    public void It_should_export_described_payload_schema_and_emit_a_problem_resource()
    {
        // Arrange
        var typeUris = new ProblemTypeUriBuilder(Portal);
        var catalog = new ProblemCatalogBuilder()
            .Add<SampleProblem>(422, true, new ProblemEndpoint("POST", "/sample"))
            .Build();
        IProblemExporter exporter = new ProblemExporter(catalog, typeUris);
        var emitter = new ProblemResourceEmitter(catalog, exporter, typeUris, Portal);

        // Act
        var export = exporter.Export(catalog.All.Single());
        var all = exporter.ExportAll();
        var resource = emitter.Emit(new ProblemResourceIdentity("dotnet", "notes", "lapras", "v1"));
        var json = emitter.Serialize(resource);

        // Assert
        export.Id.Should().Be("sample_problem");
        export.Type.Should().Be("https://docs.example.test/docs/lapras/dotnet/notes/api/v1/sample_problem");
        export.Status.Should().Be(422);
        export.Recoverable.Should().BeTrue();
        export.Endpoints.Should().ContainSingle();
        export.Schema["description"]!.GetValue<string>().Should().Contain("sample problem");
        var properties = export.Schema["properties"]!.AsObject();
        properties.Should().ContainKey("value").And.NotContainKey("id").And.NotContainKey("detail");
        properties["value"]!["description"]!.GetValue<string>().Should().Contain("sample payload");
        var allExport = all.Should().ContainSingle().Which;
        allExport.Should().BeEquivalentTo(export, options => options.Excluding(value => value.Schema));
        JsonNode.DeepEquals(allExport.Schema, export.Schema).Should().BeTrue();

        resource.ApiVersion.Should().Be("atomi.cloud/v1alpha1");
        resource.Kind.Should().Be("Problem");
        resource.Metadata.Should().Be(new ProblemResourceMetadata("notes-lapras-v1", "dotnet"));
        resource.Spec.Platform.Should().Be("dotnet");
        resource.Spec.Service.Should().Be("notes");
        resource.Spec.Landscape.Should().Be("lapras");
        resource.Spec.Version.Should().Be("v1");
        resource.Spec.Problems.Should().ContainSingle().Which.Schema.Should().NotBeSameAs(export.Schema);
        json.Should().Contain("\"apiVersion\":\"atomi.cloud/v1alpha1\"")
            .And.Contain("\"recoverable\":true")
            .And.Contain("\"endpoints\"");
    }

    [Fact]
    public void It_should_emit_each_requested_version_from_a_versioned_catalog()
    {
        // Arrange
        var typeUris = new ProblemTypeUriBuilder(Portal);
        var catalog = new ProblemCatalogBuilder()
            .Add<SampleProblem>(400, false)
            .Add<VersionTwoProblem>(409, true)
            .Build();
        var exporter = new ProblemExporter(catalog, typeUris);
        var emitter = new ProblemResourceEmitter(catalog, exporter, typeUris, Portal);

        // Act
        var versionOne = emitter.Emit(new ProblemResourceIdentity("dotnet", "notes", "lapras", "v1"));
        var versionTwo = emitter.Emit(new ProblemResourceIdentity("dotnet", "notes", "lapras", "v2"));
        var missingVersion = () => emitter.Emit(new ProblemResourceIdentity("dotnet", "notes", "lapras", "v3"));

        // Assert
        versionOne.Spec.Version.Should().Be("v1");
        versionOne.Spec.Problems.Should().ContainSingle().Which.Should().Match<ProblemResourceEntry>(entry =>
            entry.Id == "sample_problem" && entry.Type.EndsWith("/v1/sample_problem", StringComparison.Ordinal));
        versionTwo.Spec.Version.Should().Be("v2");
        versionTwo.Spec.Problems.Should().ContainSingle().Which.Should().Match<ProblemResourceEntry>(entry =>
            entry.Id == "version_two" && entry.Type.EndsWith("/v2/version_two", StringComparison.Ordinal));
        missingVersion.Should().Throw<ArgumentException>().WithMessage("*v3*");
    }

    [Fact]
    public void It_should_reject_foreign_descriptors_and_inconsistent_resource_rows()
    {
        // Arrange
        var typeUris = new ProblemTypeUriBuilder(Portal);
        var catalog = new ProblemCatalogBuilder().Add<SampleProblem>(400, false).Build();
        var exporter = new ProblemExporter(catalog, typeUris);
        var emitter = new ProblemResourceEmitter(catalog, exporter, typeUris, Portal);
        var foreign = new ProblemDescriptor(typeof(OtherProblem), "other_problem", "Other", "v1", 400, false, []);
        var valueEqualCopy = catalog.All.Single() with { };
        var emptyCatalog = new ProblemCatalogBuilder().Build();
        var emptyExporter = new ProblemExporter(emptyCatalog, typeUris);
        var emptyEmitter = new ProblemResourceEmitter(emptyCatalog, emptyExporter, typeUris, Portal);

        // Act
        var foreignAct = () => exporter.Export(foreign);
        var valueEqualCopyAct = () => exporter.Export(valueEqualCopy);
        var identityAct = () => emitter.Emit(new ProblemResourceIdentity("other", "notes", "lapras", "v1"));
        var emptyAct = () => emptyEmitter.Emit(new ProblemResourceIdentity("dotnet", "notes", "lapras", "v1"));

        // Assert
        foreignAct.Should().Throw<ArgumentException>();
        valueEqualCopyAct.Should().Throw<ArgumentException>();
        identityAct.Should().Throw<ArgumentException>();
        emptyAct.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void It_should_reject_an_exporter_that_diverges_from_the_single_URI_builder()
    {
        // Arrange
        var typeUris = new ProblemTypeUriBuilder(Portal);
        var catalog = new ProblemCatalogBuilder().Add<SampleProblem>(400, false).Build();
        var exporter = new DivergentExporter();
        var emitter = new ProblemResourceEmitter(catalog, exporter, typeUris, Portal);

        // Act
        var act = () => emitter.Emit(new ProblemResourceIdentity("dotnet", "notes", "lapras", "v1"));

        // Assert
        act.Should().Throw<InvalidOperationException>().WithMessage("*does not match*");
    }

    [Fact]
    public void It_should_validate_null_export_and_emitter_dependencies()
    {
        // Arrange
        var typeUris = new ProblemTypeUriBuilder(Portal);
        var catalog = new ProblemCatalogBuilder().Add<SampleProblem>(400, false).Build();
        var exporter = new ProblemExporter(catalog, typeUris);

        // Act
        var exporterCatalog = () => new ProblemExporter(null!, typeUris);
        var exporterUris = () => new ProblemExporter(catalog, null!);
        var descriptor = () => exporter.Export(null!);
        var emitterCatalog = () => new ProblemResourceEmitter(null!, exporter, typeUris, Portal);
        var emitterExporter = () => new ProblemResourceEmitter(catalog, null!, typeUris, Portal);
        var emitterUris = () => new ProblemResourceEmitter(catalog, exporter, null!, Portal);
        var emitterPortal = () => new ProblemResourceEmitter(catalog, exporter, typeUris, null!);
        var emitter = new ProblemResourceEmitter(catalog, exporter, typeUris, Portal);
        var identity = () => emitter.Emit(null!);
        var serialize = () => emitter.Serialize(null!);

        // Assert
        exporterCatalog.Should().Throw<ArgumentNullException>();
        exporterUris.Should().Throw<ArgumentNullException>();
        descriptor.Should().Throw<ArgumentNullException>();
        emitterCatalog.Should().Throw<ArgumentNullException>();
        emitterExporter.Should().Throw<ArgumentNullException>();
        emitterUris.Should().Throw<ArgumentNullException>();
        emitterPortal.Should().Throw<ArgumentNullException>();
        identity.Should().Throw<ArgumentNullException>();
        serialize.Should().Throw<ArgumentNullException>();
    }

    private sealed class DivergentExporter : IProblemExporter
    {
        public ProblemExport Export(ProblemDescriptor descriptor) => new(
            descriptor.Id,
            "https://wrong.example/problem",
            descriptor.Title,
            descriptor.Status,
            descriptor.Recoverable,
            new JsonObject { ["type"] = "object" },
            descriptor.Endpoints);

        public IReadOnlyList<ProblemExport> ExportAll() => [];
    }
}
