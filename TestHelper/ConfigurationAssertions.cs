using FluentAssertions;
using FluentAssertions.Execution;
using FluentAssertions.Primitives;
using Microsoft.Extensions.Configuration;

namespace AtomiCloud.Diene.Config.TestHelper;

/// <summary>Entry point for asserting on merged configuration.</summary>
public static class ConfigurationAssertionExtensions
{
    /// <summary>Begins an assertion chain over a merged configuration.</summary>
    public static ConfigurationAssertions Should(this IConfiguration configuration) => new(configuration);
}

/// <summary>
/// Assertions about what the merged configuration actually resolved to.
/// </summary>
/// <remarks>
/// Consumers otherwise write <c>config["a:b"].Should().Be("x")</c>, which reports "expected
/// x, found null" and says nothing about which spelling was looked up — the failure mode
/// these assertions exist to explain.
/// </remarks>
public sealed class ConfigurationAssertions(IConfiguration subject)
    : ReferenceTypeAssertions<IConfiguration, ConfigurationAssertions>(subject)
{
    /// <inheritdoc />
    protected override string Identifier => "configuration";

    /// <summary>Asserts that <paramref name="key" />, in any C0 spelling, resolved to <paramref name="expected" />.</summary>
    public AndConstraint<ConfigurationAssertions> HaveValue(string key, string expected, string because = "", params object[] becauseArgs)
    {
        var canonical = ConfigKey.Path(key);
        var actual = Subject[canonical];

        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(actual == expected)
            .FailWith(
                "Expected " + Identifier + " key {0} (canonically {1}) to be {2}{reason}, but found {3}.",
                key,
                canonical,
                expected,
                actual);

        return new AndConstraint<ConfigurationAssertions>(this);
    }

    /// <summary>
    /// Asserts that <paramref name="key" /> is declared but empty — the blank-in-yaml secrets
    /// convention, before the environment supplies the value.
    /// </summary>
    public AndConstraint<ConfigurationAssertions> HaveBlankValue(string key, string because = "", params object[] becauseArgs)
    {
        var canonical = ConfigKey.Path(key);
        var actual = Subject[canonical];

        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(string.IsNullOrEmpty(actual))
            .FailWith(
                "Expected " + Identifier + " key {0} (canonically {1}) to be blank{reason}, but found {2}.",
                key,
                canonical,
                actual);

        return new AndConstraint<ConfigurationAssertions>(this);
    }

    /// <summary>Asserts that a list bound from indexed keys resolved to exactly <paramref name="expected" />.</summary>
    public AndConstraint<ConfigurationAssertions> HaveList(string key, params string[] expected)
    {
        var canonical = ConfigKey.Path(key);
        var actual = Subject.GetSection(canonical).GetChildren().Select(child => child.Value).ToArray();

        Execute.Assertion
            .ForCondition(actual.SequenceEqual(expected))
            .FailWith(
                "Expected " + Identifier + " key {0} (canonically {1}) to hold {2}, but found {3}.",
                key,
                canonical,
                expected,
                actual);

        return new AndConstraint<ConfigurationAssertions>(this);
    }
}
