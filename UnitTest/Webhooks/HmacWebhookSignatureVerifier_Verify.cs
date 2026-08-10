using System.Text;
using AtomiCloud.Diene.AuthEngine.TestHelper.Fakes;
using AtomiCloud.Diene.ServerEngine.Config;
using AtomiCloud.Diene.ServerEngine.TestHelper.Builders;
using AtomiCloud.Diene.ServerEngine.TestHelper.Fakes;
using AtomiCloud.Diene.ServerEngine.Webhooks;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Webhooks;

public class HmacWebhookSignatureVerifier_Verify
{
    private static readonly DateTimeOffset Now = new(2026, 1, 1, 12, 0, 0, TimeSpan.Zero);
    private static readonly byte[] Body = Encoding.UTF8.GetBytes("""{"version":1}""");

    [Fact]
    public void It_should_accept_a_signature_over_the_exact_body_bytes()
    {
        // Arrange
        var subject = Verifier(out _, out _);
        var header = WebhookRequestSigner.Header(Now, Body);

        // Act
        var actual = subject.Verify(header, Body);

        // Assert
        actual.IsSuccess().Should().BeTrue();
    }

    [Fact]
    public void It_should_reject_a_signature_over_a_body_that_differs_by_one_byte()
    {
        // Arrange
        var subject = Verifier(out _, out _);
        var header = WebhookRequestSigner.Header(Now, Body);
        var tampered = Encoding.UTF8.GetBytes("""{"version":2}""");

        // Act
        var actual = subject.Verify(header, tampered);

        // Assert
        actual.GetFailure().Should().Be(WebhookSignatureFailure.DigestMismatch);
    }

    [Fact]
    public void It_should_reject_a_digest_computed_under_an_unknown_key()
    {
        // Arrange
        var subject = Verifier(out _, out _);
        var header = WebhookRequestSigner.Header(Now, Body, "not-the-receivers-key");

        // Act
        var actual = subject.Verify(header, Body);

        // Assert
        actual.GetFailure().Should().Be(WebhookSignatureFailure.DigestMismatch);
    }

    [Fact]
    public void It_should_reject_a_digest_signed_over_a_different_timestamp()
    {
        // Arrange — the timestamp is part of the signed payload, so replaying a valid digest
        // under a fresh t must fail even though both halves are individually well formed.
        var subject = Verifier(out _, out _);
        var digest = WebhookRequestSigner.Digest(Now.ToUnixTimeSeconds(), Body);
        var replayed = $"t={Now.AddSeconds(1).ToUnixTimeSeconds()}, v1={digest}";

        // Act
        var actual = subject.Verify(replayed, Body);

        // Assert
        actual.GetFailure().Should().Be(WebhookSignatureFailure.DigestMismatch);
    }

    [Theory]
    [ClassData(typeof(WithinWindowCases))]
    public void It_should_accept_a_timestamp_inside_the_configured_window(int offsetSeconds)
    {
        // Arrange
        var subject = Verifier(out _, out _, TimeSpan.FromSeconds(300));
        var signedAt = Now.AddSeconds(offsetSeconds);
        var header = WebhookRequestSigner.Header(signedAt, Body);

        // Act
        var actual = subject.Verify(header, Body);

        // Assert
        actual.IsSuccess().Should().BeTrue();
    }

    [Theory]
    [ClassData(typeof(OutsideWindowCases))]
    public void It_should_reject_a_timestamp_outside_the_configured_window(int offsetSeconds)
    {
        // Arrange
        var subject = Verifier(out _, out _, TimeSpan.FromSeconds(300));
        var signedAt = Now.AddSeconds(offsetSeconds);
        var header = WebhookRequestSigner.Header(signedAt, Body);

        // Act
        var actual = subject.Verify(header, Body);

        // Assert
        actual.GetFailure().Should().Be(WebhookSignatureFailure.StaleTimestamp);
    }

    [Fact]
    public void It_should_check_freshness_before_the_digest()
    {
        // Arrange — a stale delivery whose digest is ALSO wrong reports staleness, so an
        // operator investigating clock skew is not sent looking for a wrong secret.
        var subject = Verifier(out _, out _, TimeSpan.FromSeconds(10));
        var header = WebhookRequestSigner.Header(Now.AddMinutes(-30), Body, "wrong-key");

        // Act
        var actual = subject.Verify(header, Body);

        // Assert
        actual.GetFailure().Should().Be(WebhookSignatureFailure.StaleTimestamp);
    }

    [Fact]
    public void It_should_accept_a_delivery_signed_with_the_outgoing_rotation_key()
    {
        // Arrange — the contract requires every live key to be tried, which is what makes a
        // rotation possible without rejecting in-flight deliveries.
        var subject = Verifier(out _, out var secrets);
        secrets.Rotate("incoming-key");
        var header = WebhookRequestSigner.Header(Now, Body);

        // Act
        var actual = subject.Verify(header, Body);

        // Assert
        actual.IsSuccess().Should().BeTrue();
    }

    [Fact]
    public void It_should_accept_a_delivery_signed_with_the_incoming_rotation_key()
    {
        // Arrange
        var subject = Verifier(out _, out var secrets);
        secrets.Rotate("incoming-key");
        var header = WebhookRequestSigner.Header(Now, Body, "incoming-key");

        // Act
        var actual = subject.Verify(header, Body);

        // Assert
        actual.IsSuccess().Should().BeTrue();
    }

    [Fact]
    public void It_should_report_an_empty_key_set_distinctly_from_a_mismatch()
    {
        // Arrange — nothing a caller sends could pass, and the fix is on the receiver's side.
        var subject = Verifier(out _, out var secrets);
        secrets.Forget();
        var header = WebhookRequestSigner.Header(Now, Body);

        // Act
        var actual = subject.Verify(header, Body);

        // Assert
        actual.GetFailure().Should().Be(WebhookSignatureFailure.NoSigningKeys);
    }

    [Fact]
    public void It_should_pass_a_malformed_header_refusal_through_unchanged()
    {
        // Arrange
        var subject = Verifier(out _, out _);

        // Act
        var actual = subject.Verify("t=1", Body);

        // Assert
        actual.GetFailure().Should().Be(WebhookSignatureFailure.MalformedHeader);
    }

    [Fact]
    public void It_should_verify_an_empty_body()
    {
        // Arrange — an empty body is still covered by the digest; the separator byte alone
        // must not be treated as an absent payload.
        var subject = Verifier(out _, out _);
        var header = WebhookRequestSigner.Header(Now, []);

        // Act
        var actual = subject.Verify(header, []);

        // Assert
        actual.IsSuccess().Should().BeTrue();
    }

    [Fact]
    public void It_should_follow_the_clock_it_was_given()
    {
        // Arrange
        var subject = Verifier(out var clock, out _, TimeSpan.FromSeconds(60));
        var header = WebhookRequestSigner.Header(Now, Body);

        // Act
        clock.Advance(TimeSpan.FromMinutes(5));
        var actual = subject.Verify(header, Body);

        // Assert
        actual.GetFailure().Should().Be(WebhookSignatureFailure.StaleTimestamp);
    }

    private static HmacWebhookSignatureVerifier Verifier(
        out FakeAuthClock clock,
        out FakeWebhookSecretProvider secrets,
        TimeSpan? tolerance = null)
    {
        clock = new FakeAuthClock(Now);
        secrets = new FakeWebhookSecretProvider(WebhookRequestSigner.DefaultKey);
        var config = WebhookConfig.Create(tolerance ?? WebhookConfig.MaximumTolerance).Get();
        return new HmacWebhookSignatureVerifier(secrets, clock, config);
    }

    private sealed class WithinWindowCases : TheoryData<int>
    {
        public WithinWindowCases()
        {
            this.Add(0);
            this.Add(299);
            this.Add(300);
            this.Add(-300);
        }
    }

    private sealed class OutsideWindowCases : TheoryData<int>
    {
        public OutsideWindowCases()
        {
            this.Add(301);
            this.Add(-301);
            this.Add(86400);
        }
    }
}
