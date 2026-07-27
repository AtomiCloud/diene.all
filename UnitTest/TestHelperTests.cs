using AtomiCloud.Diene.Results;
using AtomiCloud.Diene.Results.TestHelper;
using FluentAssertions;

namespace AtomiCloud.Diene.Results.UnitTest;

public class TestHelperTests
{
    [Fact]
    public void Result_assertions_should_accept_and_reject_both_variants()
    {
        var success = Result.Ok<int, string>(2);
        var failure = Result.Err<int, string>("bad");

        success.Should().Subject.Equals(success).Should().BeTrue();
        success.Should().BeOk().Which.Should().Be(2);
        success.Should().BeOk(2);
        failure.Should().BeErr().Which.Should().Be("bad");
        failure.Should().BeErr(expected: "bad");

        var wrongVariant = () => success.Should().BeErr("because {0}", "test");
        wrongVariant.Should().Throw<Exception>().WithMessage("*because test*");
        var wrongValue = () => success.Should().BeOk(3);
        wrongValue.Should().Throw<Exception>();
        var wrongSuccess = () => failure.Should().BeOk();
        wrongSuccess.Should().Throw<Exception>();
        var wrongError = () => failure.Should().BeErr(expected: "other");
        wrongError.Should().Throw<Exception>();
    }

    [Fact]
    public void Option_assertions_should_accept_and_reject_both_variants()
    {
        var some = Option.Some(2);
        var none = Option.None<int>();

        some.Should().Subject.Equals(some).Should().BeTrue();
        some.Should().BeSome().Which.Should().Be(2);
        some.Should().BeSome(2);
        none.Should().BeNone();

        var wrongNone = () => some.Should().BeNone("because {0}", "test");
        wrongNone.Should().Throw<Exception>().WithMessage("*because test*");
        var wrongSome = () => none.Should().BeSome();
        wrongSome.Should().Throw<Exception>();
        var wrongValue = () => some.Should().BeSome(3);
        wrongValue.Should().Throw<Exception>();
    }

    [Fact]
    public async Task Task_assertions_should_accept_and_reject_both_variants()
    {
        var success = Task.FromResult(Result.Ok<int, string>(2));
        var failure = Task.FromResult(Result.Err<int, string>("bad"));

        (await success.Should().BeOkAsync()).Which.Should().Be(2);
        (await failure.Should().BeErrAsync()).Which.Should().Be("bad");
        var wrongSuccess = async () => await failure.Should().BeOkAsync("because {0}", "test");
        await wrongSuccess.Should().ThrowAsync<Exception>().WithMessage("*because test*");
        var wrongFailure = async () => await success.Should().BeErrAsync();
        await wrongFailure.Should().ThrowAsync<Exception>();
    }
}
