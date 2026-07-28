using AtomiCloud.Diene.ApiEngine.Client;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Client;

/// <summary>
/// The service-tree address, which doubles as the keyed-service key and the configuration key.
/// </summary>
public class ServiceAddress_Create
{
    [Fact]
    public void Accepts_lowercase_service_tree_segments_and_trims_them()
    {
        var address = ServiceAddress.Create(" lithium ", "notes", "note-archive").Get();

        address.Platform.Should().Be("lithium");
        address.Service.Should().Be("notes");
        address.Module.Should().Be("note-archive");
        address.ToString().Should().Be("lithium.notes.note-archive");
    }

    [Theory]
    [InlineData(null, "notes", "note", "platform")]
    [InlineData("  ", "notes", "note", "platform")]
    [InlineData("lithium", null, "note", "service")]
    [InlineData("lithium", "notes", "", "module")]
    public void Rejects_a_blank_segment_and_names_which_one(
        string? platform,
        string? service,
        string? module,
        string field)
    {
        var address = ServiceAddress.Create(platform, service, module);

        address.GetFailure().Field.Should().Be(field);
        address.GetFailure().Reason.Should().Contain("must not be blank");
    }

    [Theory]
    [InlineData("Lithium")]
    [InlineData("lithium_core")]
    [InlineData("1lithium")]
    [InlineData("lithium.core")]
    public void Rejects_a_segment_that_is_not_a_service_tree_name(string platform)
    {
        var address = ServiceAddress.Create(platform, "notes", "note");

        // Rejected at composition rather than at first use: an address that does not match the tree
        // becomes a keyed-service lookup that silently finds nothing, and the failure then appears at
        // the call site rather than at the registration that was wrong.
        address.GetFailure().Field.Should().Be("platform");
        address.GetFailure().Reason.Should().Contain("lowercase alphanumeric");
    }

    [Fact]
    public void Parses_the_canonical_key_form()
    {
        var address = ServiceAddress.Parse(" lithium.notes.note ").Get();

        address.ToString().Should().Be("lithium.notes.note");
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void Rejects_a_blank_key(string? key)
    {
        var address = ServiceAddress.Parse(key);

        address.GetFailure().Reason.Should().Contain("must not be blank");
    }

    [Theory]
    [InlineData("lithium.notes")]
    [InlineData("lithium.notes.note.extra")]
    [InlineData("notes")]
    public void Rejects_a_key_without_exactly_three_segments(string key)
    {
        var address = ServiceAddress.Parse(key);

        address.GetFailure().Reason.Should().Contain("three dot-separated segments");
    }

    [Fact]
    public void Propagates_a_segment_failure_out_of_parse()
    {
        var address = ServiceAddress.Parse("Lithium.notes.note");

        address.GetFailure().Field.Should().Be("platform");
    }

    [Fact]
    public void Equal_addresses_compare_and_key_identically()
    {
        var first = ServiceAddress.Create("lithium", "notes", "note").Get();
        var second = ServiceAddress.Parse("lithium.notes.note").Get();

        // Value equality matters because these are used as dictionary keys in the fakes and as
        // configuration keys; reference equality would make two spellings of one upstream distinct.
        first.Should().Be(second);
        first.GetHashCode().Should().Be(second.GetHashCode());
    }
}
