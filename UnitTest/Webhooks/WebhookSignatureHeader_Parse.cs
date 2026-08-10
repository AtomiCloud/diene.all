using AtomiCloud.Diene.ServerEngine.Webhooks;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Webhooks;

public class WebhookSignatureHeader_Parse
{
    private const string Digest = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

    [Fact]
    public void It_should_parse_a_canonical_header()
    {
        // Act
        var actual = WebhookSignatureHeader.Parse($"t=1767225600, v1={Digest}").Get();

        // Assert
        actual.Timestamp.Should().Be(1767225600);
        Convert.ToHexString(actual.Digest).ToLowerInvariant().Should().Be(Digest);
    }

    [Theory]
    [ClassData(typeof(WhitespaceCases))]
    public void It_should_tolerate_optional_whitespace_around_the_parameters(string header)
    {
        // Act
        var actual = WebhookSignatureHeader.Parse(header);

        // Assert
        actual.Get().Timestamp.Should().Be(1);
    }

    [Fact]
    public void It_should_accept_the_parameters_in_either_order()
    {
        // Act
        var actual = WebhookSignatureHeader.Parse($"v1={Digest},t=42");

        // Assert
        actual.Get().Timestamp.Should().Be(42);
    }

    [Theory]
    [ClassData(typeof(MissingHeaderCases))]
    public void It_should_report_an_absent_header_distinctly(string? header)
    {
        // Act
        var actual = WebhookSignatureHeader.Parse(header);

        // Assert
        actual.GetFailure().Should().Be(WebhookSignatureFailure.MissingHeader);
    }

    [Theory]
    [ClassData(typeof(MalformedHeaderCases))]
    public void It_should_refuse_a_header_that_is_not_exactly_one_t_and_one_v1(string header)
    {
        // Act
        var actual = WebhookSignatureHeader.Parse(header);

        // Assert
        actual.GetFailure().Should().Be(WebhookSignatureFailure.MalformedHeader);
    }

    private sealed class WhitespaceCases : TheoryData<string>
    {
        public WhitespaceCases()
        {
            this.Add($"t=1, v1={Digest}");
            this.Add($"t=1,v1={Digest}");
            this.Add($"  t = 1 ,  v1 = {Digest}  ");
        }
    }

    private sealed class MissingHeaderCases : TheoryData<string?>
    {
        public MissingHeaderCases()
        {
            this.Add(null!);
            this.Add(string.Empty);
            this.Add("   ");
        }
    }

    private sealed class MalformedHeaderCases : TheoryData<string>
    {
        public MalformedHeaderCases()
        {
            // A duplicated parameter is the shape an attacker would use to smuggle a second
            // digest past a first-match parser, so it must be refused rather than ignored.
            this.Add($"t=1, v1={Digest}, v1={Digest}");
            this.Add($"t=1, t=2, v1={Digest}");

            // An unknown parameter is refused rather than skipped.
            this.Add($"t=1, v1={Digest}, v2=deadbeef");

            // Missing halves.
            this.Add("t=1");
            this.Add($"v1={Digest}");

            // Not name=value at all.
            this.Add($"t=1, {Digest}");
            this.Add($"t=1, v1={Digest}=extra");
            this.Add("=1");

            // A signed, spaced, or non-decimal timestamp is not an unsigned base-10 value.
            this.Add($"t=-1, v1={Digest}");
            this.Add($"t=+1, v1={Digest}");
            this.Add($"t=1_000, v1={Digest}");
            this.Add($"t=1e3, v1={Digest}");
            this.Add($"t=, v1={Digest}");
            this.Add($"t=99999999999999999999, v1={Digest}");

            // Digest length and alphabet: uppercase hex is not the contract's spelling.
            this.Add("t=1, v1=abc");
            this.Add($"t=1, v1={Digest}ab");
            this.Add("t=1, v1=" + Digest.ToUpperInvariant());
            this.Add("t=1, v1=" + Digest[..63] + "g");
        }
    }
}
