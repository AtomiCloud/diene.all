using AtomiCloud.Diene.ApiEngine.Client;
using AtomiCloud.Diene.ApiEngine.Config;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Config;

/// <summary>Validation of the whole <c>HttpClient</c> block.</summary>
public class ApiEngineConfig_Create
{
    [Fact]
    public void Accepts_several_upstreams_and_keys_them_canonically()
    {
        var config = ApiEngineConfig.Create(new Dictionary<string, HttpClientOption>(StringComparer.Ordinal)
        {
            ["  lithium.notes.note  "] = ApiEngineFixture.Option(),
            ["lithium.notes.archive"] = ApiEngineFixture.Option(authResource: "https://archive.test.invalid"),
        }).Get();

        // Keyed by the canonical form rather than the literal string, so a stray space in a YAML key
        // cannot produce an upstream nothing can resolve.
        config.Upstreams.Keys.Should().BeEquivalentTo("lithium.notes.note", "lithium.notes.archive");
        config.Find(ApiEngineFixture.Notes).IsSome().Should().BeTrue();
    }

    [Fact]
    public void Rejects_an_absent_block()
    {
        var config = ApiEngineConfig.Create(null);

        config.GetFailure().Field.Should().Be(HttpClientOption.Key);
        config.GetFailure().Reason.Should().Contain("required");
    }

    [Fact]
    public void Rejects_an_empty_block()
    {
        var config = ApiEngineConfig.Create(new Dictionary<string, HttpClientOption>(StringComparer.Ordinal));

        // An empty block is a service that declares a client tree and can call nothing, which is
        // never what was meant.
        config.GetFailure().Reason.Should().Contain("At least one upstream");
    }

    [Fact]
    public void Rejects_a_key_that_is_not_a_service_tree_address()
    {
        var config = ApiEngineConfig.Create(new Dictionary<string, HttpClientOption>(StringComparer.Ordinal)
        {
            ["notes"] = ApiEngineFixture.Option(),
        });

        config.GetFailure().Field.Should().Be($"{HttpClientOption.Key}.notes");
        config.GetFailure().Reason.Should().Contain("three dot-separated segments");
    }

    [Fact]
    public void Rejects_two_keys_that_canonicalise_to_one_upstream()
    {
        var config = ApiEngineConfig.Create(new Dictionary<string, HttpClientOption>(StringComparer.Ordinal)
        {
            ["lithium.notes.note"] = ApiEngineFixture.Option(),
            [" lithium.notes.note "] = ApiEngineFixture.Option(baseAddress: "https://other.test.invalid/"),
        });

        // Last-write-wins would silently pick one base address out of two, and which one depends on
        // dictionary order — so this is rejected rather than resolved.
        config.GetFailure().Reason.Should().Contain("more than once");
    }

    [Fact]
    public void Propagates_the_failure_of_an_individual_upstream()
    {
        var config = ApiEngineConfig.Create(new Dictionary<string, HttpClientOption>(StringComparer.Ordinal)
        {
            ["lithium.notes.note"] = ApiEngineFixture.Option(timeout: "nope"),
        });

        config.GetFailure().Field.Should().Be($"{HttpClientOption.Key}.lithium.notes.note.timeout");
    }

    [Fact]
    public void Find_returns_none_for_an_unconfigured_upstream()
    {
        var config = ApiEngineFixture.Config();
        var absent = ServiceAddress.Create("lithium", "notes", "absent").Get();

        config.Find(absent).IsNone().Should().BeTrue();
    }

    [Fact]
    public void Find_rejects_a_null_address()
    {
        var config = ApiEngineFixture.Config();

        var find = () => config.Find(null!);
        find.Should().Throw<ArgumentNullException>();
    }
}
