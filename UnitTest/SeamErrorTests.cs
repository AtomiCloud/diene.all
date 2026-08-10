namespace AtomiCloud.Diene.Interfaces.UnitTest;

public class SeamErrorTests
{
    private static SeamError Sample() =>
        new(SeamKind.Vfs, "not_found", "Entry not found", "No entry exists at '/tmp/x'.");

    [Fact]
    public void It_should_expose_every_component()
    {
        var error = new SeamError(SeamKind.Terminal, "launch_failed", "Launch", "boom", [new("executable", "nope")]);

        error.Seam.Should().Be(SeamKind.Terminal);
        error.Id.Should().Be("launch_failed");
        error.Title.Should().Be("Launch");
        error.Detail.Should().Be("boom");
        error.Data.Should().ContainKey("executable").WhoseValue.Should().Be("nope");
    }

    [Fact]
    public void It_should_default_to_empty_context()
    {
        Sample().Data.Should().BeEmpty();
    }

    [Fact]
    public void It_should_add_context_without_mutating_the_original()
    {
        var error = Sample();

        var enriched = error.With("path", "/tmp/x");

        enriched.Data.Should().ContainKey("path");
        error.Data.Should().BeEmpty();
    }

    [Fact]
    public void It_should_replace_an_existing_context_entry()
    {
        Sample().With("path", "/a").With("path", "/b").Data["path"].Should().Be("/b");
    }

    [Fact]
    public void It_should_reject_a_blank_id()
    {
        var act = () => new SeamError(SeamKind.Vfs, "  ", "Title", "Detail");

        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void It_should_reject_a_null_title_or_detail()
    {
        var title = () => new SeamError(SeamKind.Vfs, "id", null!, "Detail");
        var detail = () => new SeamError(SeamKind.Vfs, "id", "Title", null!);

        title.Should().Throw<ArgumentNullException>();
        detail.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_reject_a_blank_context_key_or_null_value()
    {
        var key = () => Sample().With("  ", "value");
        var value = () => Sample().With("key", null!);

        key.Should().Throw<ArgumentException>();
        value.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void It_should_be_equal_by_value()
    {
        var left = Sample().With("path", "/tmp/x");
        var right = Sample().With("path", "/tmp/x");

        left.Equals(right).Should().BeTrue();
        left.Equals((object)right).Should().BeTrue();
        (left == right).Should().BeTrue();
        (left != right).Should().BeFalse();
        left.GetHashCode().Should().Be(right.GetHashCode());
    }

    [Theory]
    [InlineData(SeamKind.System, "not_found", "Entry not found", "No entry exists at '/tmp/x'.")]
    [InlineData(SeamKind.Vfs, "other", "Entry not found", "No entry exists at '/tmp/x'.")]
    [InlineData(SeamKind.Vfs, "not_found", "Other", "No entry exists at '/tmp/x'.")]
    [InlineData(SeamKind.Vfs, "not_found", "Entry not found", "Other")]
    public void It_should_differ_on_any_component(SeamKind seam, string id, string title, string detail)
    {
        Sample().Equals(new SeamError(seam, id, title, detail)).Should().BeFalse();
    }

    [Fact]
    public void It_should_differ_on_context()
    {
        Sample().With("path", "/a").Equals(Sample().With("path", "/b")).Should().BeFalse();
        Sample().With("path", "/a").Equals(Sample()).Should().BeFalse();
    }

    [Fact]
    public void It_should_not_equal_null_or_another_type()
    {
        var error = Sample();
        SeamError? absent = null;

        error.Equals(null).Should().BeFalse();
        Equals(error, "text").Should().BeFalse();
        Equals(error, null).Should().BeFalse();
        (error == absent).Should().BeFalse();
        (absent == error).Should().BeFalse();
        (absent == null).Should().BeTrue();
    }

    [Fact]
    public void It_should_render_seam_id_and_detail()
    {
        Sample().ToString().Should().Be("vfs/not_found: No entry exists at '/tmp/x'.");
    }

    [Fact]
    public void It_should_publish_one_canonical_catalog_entry_per_failure_mode()
    {
        SeamError[] catalog =
        [
            SeamErrors.InvalidArgument(SeamKind.System, "name", "blank"),
            SeamErrors.NotFound("/tmp/a"),
            SeamErrors.AlreadyExists("/tmp/a"),
            SeamErrors.NotADirectory("/tmp/a"),
            SeamErrors.DirectoryNotEmpty("/tmp/a"),
            SeamErrors.IoFailure(SeamKind.Vfs, "read", "disk"),
            SeamErrors.EnvironmentUnavailable("HOME", "denied"),
            SeamErrors.LaunchFailed("nope", "missing"),
            SeamErrors.EmitFailed(SeamKind.Metrics, "closed"),
            SeamErrors.Cancelled(SeamKind.Terminal, "run"),
            SeamErrors.InvalidWire("instant", "nope"),
            SeamErrors.UnknownTimeZone("Mars/Olympus", "unknown"),
        ];

        catalog.Select(error => error.Id).Should().OnlyHaveUniqueItems();
        catalog.Should().AllSatisfy(error => error.Detail.Should().NotBeNullOrWhiteSpace());
    }

    [Theory]
    [InlineData("invalid_argument", SeamKind.System)]
    [InlineData("not_found", SeamKind.Vfs)]
    [InlineData("launch_failed", SeamKind.Terminal)]
    [InlineData("emit_failed", SeamKind.Metrics)]
    public void It_should_bind_each_catalog_entry_to_its_seam(string id, SeamKind seam)
    {
        SeamError[] catalog =
        [
            SeamErrors.InvalidArgument(SeamKind.System, "name", "blank"),
            SeamErrors.NotFound("/tmp/a"),
            SeamErrors.LaunchFailed("nope", "missing"),
            SeamErrors.EmitFailed(SeamKind.Metrics, "closed"),
        ];

        catalog.Single(error => error.Id == id).Seam.Should().Be(seam);
    }

    [Fact]
    public void It_should_carry_structured_context_on_catalog_entries()
    {
        SeamErrors.InvalidArgument(SeamKind.System, "name", "blank").Data["argument"].Should().Be("name");
        SeamErrors.NotFound("/tmp/a").Data["path"].Should().Be("/tmp/a");
        SeamErrors.AlreadyExists("/tmp/a").Data["path"].Should().Be("/tmp/a");
        SeamErrors.NotADirectory("/tmp/a").Data["path"].Should().Be("/tmp/a");
        SeamErrors.DirectoryNotEmpty("/tmp/a").Data["path"].Should().Be("/tmp/a");
        SeamErrors.IoFailure(SeamKind.Vfs, "read", "disk").Data["operation"].Should().Be("read");
        SeamErrors.EnvironmentUnavailable("HOME", "denied").Data["variable"].Should().Be("HOME");
        SeamErrors.LaunchFailed("nope", "missing").Data["executable"].Should().Be("nope");
        SeamErrors.EmitFailed(SeamKind.Metrics, "closed").Data.Should().BeEmpty();
        SeamErrors.Cancelled(SeamKind.Terminal, "run").Data["operation"].Should().Be("run");
        SeamErrors.InvalidWire("instant", "nope").Data["field"].Should().Be("instant");
        SeamErrors.UnknownTimeZone("Mars/Olympus", "unknown").Data["timeZone"].Should().Be("Mars/Olympus");
    }
}
