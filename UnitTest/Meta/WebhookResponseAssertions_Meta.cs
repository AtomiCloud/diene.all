using System.Net;
using AtomiCloud.Diene.ServerEngine.TestHelper.Assertions;
using AtomiCloud.Diene.ServerEngine.Webhooks;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Meta;

/// <summary>
/// Assert-the-asserter for the tri-state reply assertions.
/// </summary>
/// <remarks>
/// Every helper is exercised on a status it must accept AND on a status it must refuse. Proving
/// only the accepting half would leave a helper that returns unconditionally indistinguishable
/// from one that checks: a validator that has never failed cannot be told apart from one that
/// cannot fail, and the whole reason these helpers exist is to refuse a plausible wrong status.
/// </remarks>
public class WebhookResponseAssertions_Meta
{
    [Fact]
    public void It_should_accept_exactly_200_as_processed()
    {
        // Arrange
        using var response = Response(WebhookProtocol.ProcessedStatus);

        // Act
        var act = () => response.ShouldBeProcessed();

        // Assert
        act.Should().NotThrow();
    }

    [Theory]
    [ClassData(typeof(NotProcessedCases))]
    public void It_should_refuse_any_other_status_as_processed(int status)
    {
        // Arrange — C0 treats every other 2xx as a real endpoint failure, so a success-range
        // check would pass a reply mercury would retry for 72 hours.
        using var response = Response(status);

        // Act
        var act = () => response.ShouldBeProcessed();

        // Assert
        act.Should().Throw<Exception>().WithMessage("*mean processed with status 200*");
    }

    [Fact]
    public void It_should_accept_exactly_421_as_not_mine()
    {
        // Arrange
        using var response = Response(WebhookProtocol.NotMineStatus);

        // Act
        var act = () => response.ShouldBeNotMine();

        // Assert
        act.Should().NotThrow();
    }

    [Fact]
    public void It_should_refuse_404_as_not_mine_and_say_why()
    {
        // Arrange — this is the mistake the helper exists to catch: 404 reads as a real endpoint
        // failure, so a receiver using it to disown an event is retried for the full window.
        using var response = Response((int)HttpStatusCode.NotFound);

        // Act
        var act = () => response.ShouldBeNotMine();

        // Assert
        act.Should().Throw<Exception>()
            .WithMessage("*404 is never an ownership signal*");
    }

    [Fact]
    public void It_should_refuse_200_as_not_mine()
    {
        // Arrange
        using var response = Response(WebhookProtocol.ProcessedStatus);

        // Act
        var act = () => response.ShouldBeNotMine();

        // Assert
        act.Should().Throw<Exception>().WithMessage("*mean not mine with status 421*");
    }

    [Fact]
    public void It_should_accept_401_as_a_rejected_signature()
    {
        // Arrange
        using var response = Response((int)HttpStatusCode.Unauthorized);

        // Act
        var act = () => response.ShouldBeSignatureRejected();

        // Assert
        act.Should().NotThrow();
    }

    [Fact]
    public void It_should_refuse_421_as_a_rejected_signature()
    {
        // Arrange — 421 for an unverifiable signature would make mercury recompile an address
        // that was never wrong, hiding a credential problem as a routing one.
        using var response = Response(WebhookProtocol.NotMineStatus);

        // Act
        var act = () => response.ShouldBeSignatureRejected();

        // Assert
        act.Should().Throw<Exception>().WithMessage("*mean signature rejected with status 401*");
    }

    [Fact]
    public void It_should_accept_415_as_an_unsupported_media_type()
    {
        // Arrange
        using var response = Response((int)HttpStatusCode.UnsupportedMediaType);

        // Act
        var act = () => response.ShouldBeUnsupportedMedia();

        // Assert
        act.Should().NotThrow();
    }

    [Fact]
    public void It_should_refuse_400_as_an_unsupported_media_type()
    {
        // Arrange
        using var response = Response((int)HttpStatusCode.BadRequest);

        // Act
        var act = () => response.ShouldBeUnsupportedMedia();

        // Assert
        act.Should().Throw<Exception>().WithMessage("*mean unsupported media type with status 415*");
    }

    [Fact]
    public void It_should_accept_400_as_a_malformed_envelope()
    {
        // Arrange
        using var response = Response((int)HttpStatusCode.BadRequest);

        // Act
        var act = () => response.ShouldBeMalformedEnvelope();

        // Assert
        act.Should().NotThrow();
    }

    [Fact]
    public void It_should_refuse_415_as_a_malformed_envelope()
    {
        // Arrange
        using var response = Response((int)HttpStatusCode.UnsupportedMediaType);

        // Act
        var act = () => response.ShouldBeMalformedEnvelope();

        // Assert
        act.Should().Throw<Exception>().WithMessage("*mean malformed envelope with status 400*");
    }

    [Fact]
    public void It_should_return_the_response_so_assertions_chain()
    {
        // Arrange
        using var response = Response(WebhookProtocol.ProcessedStatus);

        // Act
        var actual = response.ShouldBeProcessed();

        // Assert
        actual.Should().BeSameAs(response);
    }

    [Fact]
    public void It_should_refuse_a_null_response()
    {
        // Act
        var act = () => WebhookResponseAssertions.ShouldBeProcessed(null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    private static HttpResponseMessage Response(int status) => new((HttpStatusCode)status);

    private sealed class NotProcessedCases : TheoryData<int>
    {
        public NotProcessedCases()
        {
            this.Add(201);
            this.Add(202);
            this.Add(204);
            this.Add(299);
            this.Add(WebhookProtocol.NotMineStatus);
            this.Add(500);
        }
    }
}
