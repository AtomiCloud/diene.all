using AtomiCloud.Diene.AuthEngine.Config;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Config;

public class TokenLifetimeConfig_Create
{
    [Fact]
    public void Defaults_match_the_alcohol_parity_lifetimes()
    {
        // These exact values are the contract, not an implementation detail: 10-minute
        // access tokens and 14-day rotating refresh tokens.
        TokenLifetimeConfig.Default.Access.Should().Be(TimeSpan.FromMinutes(10));
        TokenLifetimeConfig.Default.Refresh.Should().Be(TimeSpan.FromDays(14));
        TokenLifetimeConfig.Default.ExpirySkew.Should().Be(TimeSpan.FromSeconds(30));
        TokenLifetimeConfig.Default.RotateRefreshTokens.Should().BeTrue();

        TokenLifetimeConfig.DefaultAccessLifetime.Should().Be(TimeSpan.FromMinutes(10));
        TokenLifetimeConfig.DefaultRefreshLifetime.Should().Be(TimeSpan.FromDays(14));
        TokenLifetimeConfig.DefaultExpirySkew.Should().Be(TimeSpan.FromSeconds(30));
    }

    [Fact]
    public void Accepts_custom_positive_lifetimes()
    {
        var config = TokenLifetimeConfig.Create(
            TimeSpan.FromMinutes(5),
            TimeSpan.FromDays(1),
            TimeSpan.Zero,
            false);

        var value = config.Get();
        value.Access.Should().Be(TimeSpan.FromMinutes(5));
        value.Refresh.Should().Be(TimeSpan.FromDays(1));
        value.ExpirySkew.Should().Be(TimeSpan.Zero);
        value.RotateRefreshTokens.Should().BeFalse();
    }

    [Fact]
    public void Rejects_a_non_positive_access_lifetime() =>
        TokenLifetimeConfig.Create(TimeSpan.Zero, TimeSpan.FromDays(1), TimeSpan.Zero, true)
            .GetFailure().Field.Should().Be("lifetimes.access");

    [Fact]
    public void Rejects_a_non_positive_refresh_lifetime() =>
        TokenLifetimeConfig.Create(TimeSpan.FromMinutes(1), TimeSpan.Zero, TimeSpan.Zero, true)
            .GetFailure().Field.Should().Be("lifetimes.refresh");

    [Fact]
    public void Rejects_a_negative_skew() =>
        TokenLifetimeConfig.Create(
                TimeSpan.FromMinutes(1),
                TimeSpan.FromDays(1),
                TimeSpan.FromSeconds(-1),
                true)
            .GetFailure().Field.Should().Be("lifetimes.expirySkew");

    [Fact]
    public void Rejects_a_refresh_lifetime_that_does_not_outlive_the_access_lifetime()
    {
        // Refreshing cannot renew a token if the refresh credential dies first, so this
        // combination is rejected rather than accepted and left to fail in production.
        var config = TokenLifetimeConfig.Create(
            TimeSpan.FromMinutes(10),
            TimeSpan.FromMinutes(10),
            TimeSpan.Zero,
            true);

        var error = config.GetFailure();
        error.Field.Should().Be("lifetimes.refresh");
        error.Reason.Should().Contain("must exceed the access lifetime");
    }
}
