using AtomiCloud.Diene.Config.TestHelper;
using Microsoft.Extensions.Configuration;

namespace AtomiCloud.DotnetBase.UnitTest;

/// <summary>
/// Meta tier — assert-the-asserter. Every assertion helper is proven to PASS on a known-good
/// case and to FAIL on a known-bad one, because an assertion that cannot fail is worse than
/// no assertion at all.
/// </summary>
public class MetaConfigurationAssertionTests
{
    private static IConfiguration Config() => new AtomiConfigFixture()
        .WithBase("error_portal:host", "alpha")
        .WithBase("error_portal:signing_key", null)
        .WithBase("error_portal:retry_hosts:0", "one")
        .WithBase("error_portal:retry_hosts:1", "two")
        .Build();

    [Fact]
    public void HaveValue_passes_on_a_matching_value() =>
        Config().Should().HaveValue("error_portal:host", "alpha");

    [Fact]
    public void HaveValue_accepts_any_spelling_of_the_key() =>
        Config().Should().HaveValue("ErrorPortal:Host", "alpha");

    [Fact]
    public void HaveValue_fails_on_a_different_value_and_names_both_spellings() =>
        FluentActions.Invoking(() => Config().Should().HaveValue("error_portal:host", "beta"))
            .Should().Throw<Xunit.Sdk.XunitException>()
            .WithMessage("*error_portal:host*errorportal:host*beta*alpha*");

    [Fact]
    public void HaveValue_fails_on_an_absent_key() =>
        FluentActions.Invoking(() => Config().Should().HaveValue("nope", "beta"))
            .Should().Throw<Xunit.Sdk.XunitException>();

    [Fact]
    public void HaveValue_reports_the_supplied_reason() =>
        FluentActions.Invoking(() => Config().Should().HaveValue("error_portal:host", "beta", "the overlay sets it"))
            .Should().Throw<Xunit.Sdk.XunitException>()
            .WithMessage("*the overlay sets it*");

    [Fact]
    public void HaveBlankValue_passes_on_the_blank_in_yaml_secrets_convention() =>
        Config().Should().HaveBlankValue("error_portal:signing_key");

    [Fact]
    public void HaveBlankValue_passes_on_a_key_that_is_not_there_at_all() =>
        Config().Should().HaveBlankValue("error_portal:absent");

    [Fact]
    public void HaveBlankValue_fails_once_the_key_actually_carries_a_value() =>
        FluentActions.Invoking(() => Config().Should().HaveBlankValue("error_portal:host"))
            .Should().Throw<Xunit.Sdk.XunitException>()
            .WithMessage("*to be blank*alpha*");

    [Fact]
    public void HaveBlankValue_reports_the_supplied_reason() =>
        FluentActions.Invoking(() => Config().Should().HaveBlankValue("error_portal:host", "nothing injects it"))
            .Should().Throw<Xunit.Sdk.XunitException>()
            .WithMessage("*nothing injects it*");

    [Fact]
    public void HaveList_passes_on_the_exact_indexed_sequence() =>
        Config().Should().HaveList("error_portal:retry_hosts", "one", "two");

    [Fact]
    public void HaveList_fails_when_an_element_differs() =>
        FluentActions.Invoking(() => Config().Should().HaveList("error_portal:retry_hosts", "one", "three"))
            .Should().Throw<Xunit.Sdk.XunitException>();

    [Fact]
    public void HaveList_fails_when_the_lengths_differ() =>
        FluentActions.Invoking(() => Config().Should().HaveList("error_portal:retry_hosts", "one"))
            .Should().Throw<Xunit.Sdk.XunitException>();

    [Fact]
    public void HaveList_fails_on_a_key_holding_no_list() =>
        FluentActions.Invoking(() => Config().Should().HaveList("error_portal:host", "one"))
            .Should().Throw<Xunit.Sdk.XunitException>();

    [Fact]
    public void A_failure_names_the_subject_a_configuration() =>
        FluentActions.Invoking(() => Config().Should().HaveValue("error_portal:host", "beta"))
            .Should().Throw<Xunit.Sdk.XunitException>()
            .WithMessage("Expected configuration key*");

    [Fact]
    public void Every_assertion_returns_a_constraint_so_assertions_chain() =>
        Config().Should()
            .HaveValue("error_portal:host", "alpha").And
            .HaveBlankValue("error_portal:signing_key").And
            .HaveList("error_portal:retry_hosts", "one", "two");
}
