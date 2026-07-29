using System.ComponentModel.DataAnnotations;
using AtomiCloud.Diene.ApiEngine.Config;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Config;

/// <summary>
/// The engine-owned config block's own shape: its section key, its defaults, and the annotations a
/// consumer's validator reads.
/// </summary>
public class HttpClientOption_Schema
{
    [Fact]
    public void Declares_the_section_key_the_family_composes_under()
    {
        HttpClientOption.Key.Should().Be("HttpClient");
    }

    [Fact]
    public void Defaults_to_an_unauthenticated_upstream_with_a_thirty_second_iso_timeout()
    {
        var option = new HttpClientOption();

        option.BaseAddress.Should().BeEmpty();
        option.Timeout.Should().Be("PT30S");
        option.AuthResource.Should().BeNull();
        option.AuthScopes.Should().BeEmpty();
        option.RescueRoutingEnabled.Should().BeFalse("a server runtime's rescue is a redeploy");
    }

    [Fact]
    public void Carries_the_annotations_a_consumer_validates_the_block_with()
    {
        var option = new HttpClientOption();
        var results = new List<ValidationResult>();

        var valid = Validator.TryValidateObject(option, new ValidationContext(option), results, true);

        // Asserted through the real validator rather than by reflecting over attributes: the property
        // that matters is that a blank block FAILS validation, not that an attribute is present.
        valid.Should().BeFalse();
        results.Should().Contain(result => result.MemberNames.Contains(nameof(HttpClientOption.BaseAddress)));
    }

    [Fact]
    public void Accepts_a_populated_block_through_the_same_validator()
    {
        var option = ApiEngineFixture.Option();
        var results = new List<ValidationResult>();

        Validator.TryValidateObject(option, new ValidationContext(option), results, true).Should().BeTrue();
        results.Should().BeEmpty();
    }

    [Fact]
    public void Collects_scopes_into_the_get_only_list_a_binder_populates()
    {
        var option = new HttpClientOption();

        option.AuthScopes.Add("notes:read");

        option.AuthScopes.Should().Equal("notes:read");
    }
}
