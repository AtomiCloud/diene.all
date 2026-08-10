using AtomiCloud.Diene.ApiEngine.Config;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Config;

/// <summary>
/// Validation of one upstream entry. Every rejection names its field, because the value of a
/// total validator is that a misconfigured service tells you which line to fix.
/// </summary>
public class UpstreamConfig_Create
{
    [Fact]
    public void Accepts_a_complete_entry_and_resolves_the_iso_duration()
    {
        var config = UpstreamConfig
            .Create("HttpClient.lithium.notes.note", ApiEngineFixture.Option(
                timeout: "PT1M30S",
                authResource: " https://notes.test.invalid ",
                rescueRoutingEnabled: true,
                scopes: ["notes:read", "  ", " notes:write "]))
            .Get();

        config.BaseAddress.Should().Be(new Uri(ApiEngineFixture.BaseAddress));
        config.Timeout.Should().Be(TimeSpan.FromSeconds(90));
        config.AuthResource.Should().Be("https://notes.test.invalid", "the resource is trimmed");
        config.RescueRoutingEnabled.Should().BeTrue();

        // Blank scopes are dropped rather than sent as empty strings: an IdP asked for a scope of ""
        // fails the whole acquisition, which would read as a credential problem rather than a typo.
        config.AuthScopes.Should().Equal("notes:read", "notes:write");
    }

    [Fact]
    public void Rejects_a_missing_entry()
    {
        var config = UpstreamConfig.Create("HttpClient.a.b.c", null);

        config.GetFailure().Field.Should().Be("HttpClient.a.b.c");
        config.GetFailure().Reason.Should().Contain("required");
    }

    [Theory]
    [InlineData("", "must not be blank")]
    [InlineData("   ", "must not be blank")]
    [InlineData("notes.test.invalid", "absolute http or https")]
    [InlineData("ftp://notes.test.invalid/", "absolute http or https")]
    [InlineData("https://notes.test.invalid/?a=1", "query or fragment")]
    [InlineData("https://notes.test.invalid/#top", "query or fragment")]
    public void Rejects_a_base_address_that_is_not_one_hostname(string baseAddress, string reason)
    {
        var config = UpstreamConfig.Create("HttpClient.a.b.c", ApiEngineFixture.Option(baseAddress: baseAddress));

        config.GetFailure().Field.Should().Be("HttpClient.a.b.c.baseAddress");
        config.GetFailure().Reason.Should().Contain(reason);
    }

    [Theory]
    [InlineData("30s")]
    [InlineData("")]
    [InlineData("PT")]
    public void Rejects_a_timeout_that_is_not_an_iso_duration(string timeout)
    {
        var config = UpstreamConfig.Create("HttpClient.a.b.c", ApiEngineFixture.Option(timeout: timeout));

        config.GetFailure().Field.Should().Be("HttpClient.a.b.c.timeout");

        // The rejection quotes what it received: "invalid duration" alone leaves the reader guessing
        // which of several duration-ish spellings was wrong.
        config.GetFailure().Reason.Should().Contain("ISO 8601");
    }

    [Theory]
    [InlineData("PT0S")]
    [InlineData("-PT5S")]
    public void Rejects_a_timeout_that_is_not_positive(string timeout)
    {
        var config = UpstreamConfig.Create("HttpClient.a.b.c", ApiEngineFixture.Option(timeout: timeout));

        config.GetFailure().Field.Should().Be("HttpClient.a.b.c.timeout");
        config.GetFailure().Reason.Should().Contain("greater than zero");
    }

    [Fact]
    public void Rejects_a_null_timeout_the_way_it_rejects_a_malformed_one()
    {
        var option = ApiEngineFixture.Option();
        option.Timeout = null!;

        var config = UpstreamConfig.Create("HttpClient.a.b.c", option);

        // A binder that never visited the key leaves it null rather than blank, so the null path is a
        // real input rather than a defensive one.
        config.GetFailure().Field.Should().Be("HttpClient.a.b.c.timeout");
    }

    [Fact]
    public void The_failure_renders_as_one_diagnostic_line()
    {
        var config = UpstreamConfig.Create("HttpClient.a.b.c", ApiEngineFixture.Option(baseAddress: ""));

        config.GetFailure().ToString()
            .Should().Be("HttpClient.a.b.c.baseAddress: Base address must not be blank.");
    }

    [Fact]
    public void Rejects_scopes_declared_without_a_resource()
    {
        var config = UpstreamConfig.Create(
            "HttpClient.a.b.c",
            ApiEngineFixture.Option(authResource: null, scopes: ["notes:read"]));

        // Silently ignoring the scopes would leave a reader believing the upstream is authenticated,
        // which is the belief most likely to make a 401 look like a server fault.
        config.GetFailure().Field.Should().Be("HttpClient.a.b.c.authScopes");
        config.GetFailure().Reason.Should().Contain("unauthenticated upstream");
    }

    [Fact]
    public void Accepts_an_unauthenticated_entry_with_no_scopes()
    {
        var config = UpstreamConfig.Create("HttpClient.a.b.c", ApiEngineFixture.Option()).Get();

        config.AuthResource.Should().BeNull();
        config.AuthScopes.Should().BeEmpty();
        config.RescueRoutingEnabled.Should().BeFalse();
    }

    [Fact]
    public void Treats_a_blank_resource_as_absent()
    {
        var config = UpstreamConfig.Create("HttpClient.a.b.c", ApiEngineFixture.Option(authResource: "   ")).Get();

        config.AuthResource.Should().BeNull();
    }
}
