using AtomiCloud.Diene.Results;
using AtomiCloud.Diene.Results.TestHelper;
using FluentAssertions;
using FluentAssertions.Execution;

namespace AtomiCloud.Diene.Results.UnitTest;

public class ResultTests
{
    [Fact]
    public void It_should_create_inspect_map_and_extract_both_variants()
    {
        Result<int, string> success = Result.Ok<int, string>(2);
        Result<int, string> failure = Result.Err<int, string>("bad");

        success.IsSuccess().Should().BeTrue();
        success.IsFailure().Should().BeFalse();
        success.IsSuccess(out var value).Should().BeTrue();
        value.Should().Be(2);
        success.IsFailure(out var absentError).Should().BeFalse();
        absentError.Should().BeNull();
        failure.IsSuccess(out var absentValue).Should().BeFalse();
        absentValue.Should().Be(0);
        failure.IsFailure(out var error).Should().BeTrue();
        error.Should().Be("bad");

        success.Map(x => x * 2).Should().BeOk(4);
        failure.Map(x => x * 2).Should().BeErr("bad");
        success.MapFailure(errorValue => errorValue.Length).Should().BeOk(2);
        failure.MapFailure(errorValue => errorValue.Length).Should().BeErr(3);
        success.Get().Should().Be(2);
        failure.GetFailure().Should().Be("bad");
        success.GetOr(9).Should().Be(2);
        failure.GetOr(9).Should().Be(9);
        success.GetOr(errorValue => errorValue.Length).Should().Be(2);
        failure.GetOr(errorValue => errorValue.Length).Should().Be(3);
        success.SuccessOrDefault(9).Should().Be(2);
        failure.SuccessOrDefault(9).Should().Be(9);
        success.FailureOrDefault("fallback").Should().Be("fallback");
        failure.FailureOrDefault("fallback").Should().Be("bad");
        success.Ok().Should().BeSome(2);
        success.Err().Should().BeNone();
        failure.Ok().Should().BeNone();
        failure.Err().Should().BeSome("bad");
    }

    [Fact]
    public void It_should_compose_and_capture_only_matching_exceptions()
    {
        var success = Result.Ok<int, string>(2);
        var failure = Result.Err<int, string>("bad");
        var observed = 0;

        success.Then(x => Result.Ok<int, string>(x + 1)).Should().BeOk(3);
        failure.Then(x => Result.Ok<int, string>(x + 1)).Should().BeErr("bad");
        success.Then(x => x + 2, Errors.MapAll, exception => exception.Message).Should().BeOk(4);
        failure.Then(x => x + 2, Errors.MapAll, exception => exception.Message).Should().BeErr("bad");
        success.Then<int>(_ => throw new InvalidOperationException("captured"), Errors.MapAll, exception => exception.Message)
            .Should().BeErr("captured");
        var uncaptured = () => success.Then<int>(_ => throw new InvalidOperationException("escaped"), Errors.MapNone, exception => exception.Message);
        uncaptured.Should().Throw<InvalidOperationException>().WithMessage("escaped");
        success.Then(value => { observed = value; }, Errors.MapAll, exception => exception.Message).Should().BeOk(new Unit());
        success.Then(_ => throw new InvalidOperationException("action"), Errors.MapAll, exception => exception.Message)
            .Should().BeErr("action");

        success.OrElse(error => Result.Ok<int, string>(error.Length)).Should().BeOk(2);
        failure.OrElse(error => Result.Ok<int, string>(error.Length)).Should().BeOk(3);

        success.Do(value => observed = value).Should().BeOk(2);
        failure.Do(value => observed = value).Should().BeErr("bad");
        observed.Should().Be(2);
        success.Do(_ => throw new InvalidOperationException("side"), Errors.MapAll, exception => exception.Message)
            .Should().BeErr("side");
        success.Do(value => observed = value + 1, Errors.MapAll, exception => exception.Message).Should().BeOk(2);
        failure.Do(_ => throw new InvalidOperationException(), Errors.MapAll, exception => exception.Message).Should().BeErr("bad");
        var sideEscape = () => success.Do(_ => throw new InvalidOperationException("escaped"), Errors.MapNone, exception => exception.Message);
        sideEscape.Should().Throw<InvalidOperationException>();
        failure.DoFailure(error => observed = error.Length).Should().BeErr("bad");
        success.DoFailure(error => observed = error.Length).Should().BeOk(2);
        observed.Should().Be(3);
    }

    [Fact]
    public void It_should_assert_branch_and_match_exhaustively()
    {
        var success = Result.Ok<int, string>(2);
        var failure = Result.Err<int, string>("bad");

        success.Assert(x => Result.Ok<bool, string>(x == 2), _ => "assert").Should().BeOk(2);
        success.Assert(_ => Result.Ok<bool, string>(false), _ => "assert").Should().BeErr("assert");
        success.Assert(_ => Result.Err<bool, string>("predicate"), _ => "assert").Should().BeErr("predicate");
        failure.Assert(_ => Result.Ok<bool, string>(true), _ => "assert").Should().BeErr("bad");
        success.Assert(x => x == 2, _ => "assert", Errors.MapAll, exception => exception.Message).Should().BeOk(2);
        success.Assert(_ => false, _ => "assert", Errors.MapAll, exception => exception.Message).Should().BeErr("assert");
        success.Assert(_ => throw new InvalidOperationException("assert-throw"), _ => "assert", Errors.MapAll, exception => exception.Message)
            .Should().BeErr("assert-throw");

        success.If(_ => Result.Ok<bool, string>(true), x => Result.Ok<string, string>($"yes{x}"), x => Result.Ok<string, string>($"no{x}"))
            .Should().BeOk("yes2");
        success.If(_ => Result.Ok<bool, string>(false), x => Result.Ok<string, string>($"yes{x}"), x => Result.Ok<string, string>($"no{x}"))
            .Should().BeOk("no2");
        success.If(_ => Result.Err<bool, string>("predicate"), x => Result.Ok<string, string>($"yes{x}"), x => Result.Ok<string, string>($"no{x}"))
            .Should().BeErr("predicate");
        failure.If(_ => Result.Ok<bool, string>(true), x => Result.Ok<string, string>($"yes{x}"), x => Result.Ok<string, string>($"no{x}"))
            .Should().BeErr("bad");

        success.Match(x => x.ToString(), error => error).Should().Be("2");
        failure.Match(x => x.ToString(), error => error).Should().Be("bad");
        var observed = "";
        success.Match(x => observed = x.ToString(), error => observed = error);
        observed.Should().Be("2");
        failure.Match(x => observed = x.ToString(), error => observed = error);
        observed.Should().Be("bad");
    }

    [Fact]
    public void It_should_fail_loudly_for_wrong_or_default_extraction()
    {
        var success = Result.Ok<int, string>(2);
        var failure = Result.Err<int, string>("bad");

        var getFailure = () => failure.Get();
        getFailure.Should().Throw<UnwrapException>()
            .Which.Should().Match<UnwrapException>(exception => exception.ExpectedVariant == "Success" && Equals(exception.ActualValue, "bad"));
        var getSuccess = () => success.GetFailure();
        getSuccess.Should().Throw<UnwrapException>()
            .Which.Should().Match<UnwrapException>(exception => exception.ExpectedVariant == "Failure" && Equals(exception.ActualValue, 2));
        new UnwrapException("Some", null).Message.Should().Contain("Some");
        new InvalidResultException().Message.Should().Contain("default-initialized");

        var invalid = default(Result<int, string>);
        var inspect = () => invalid.IsSuccess();
        inspect.Should().Throw<InvalidResultException>();
        var equality = () => invalid.Equals(success);
        equality.Should().Throw<InvalidResultException>();
    }

    [Fact]
    public void It_should_support_value_semantics_and_implicit_conversions()
    {
        Result<int, string> success = 2;
        Result<int, string> failure = "bad";
        var twin = Result.Ok<int, string>(2);

        (success == twin).Should().BeTrue();
        (success != failure).Should().BeTrue();
        success.Equals((object)twin).Should().BeTrue();
        success.Equals("not a result").Should().BeFalse();
        success.GetHashCode().Should().Be(twin.GetHashCode());
        success.ToString().Should().Be("Success(2)");
        failure.ToString().Should().Be("Failure(bad)");
        failure.GetHashCode().Should().NotBe(success.GetHashCode());
    }

    [Fact]
    public void It_should_expose_exception_filter_composition()
    {
        Errors.MapAll(new Exception()).Should().BeTrue();
        Errors.MapNone(new Exception()).Should().BeFalse();
        var filter = Errors.MapIfExceptionIs<InvalidOperationException>().Or<ArgumentException>();
        filter(new InvalidOperationException()).Should().BeTrue();
        filter(new ArgumentException()).Should().BeTrue();
        filter(new IOException()).Should().BeFalse();
        var act = () => Errors.Or<Exception>(null!);
        act.Should().Throw<ArgumentNullException>();

        Result<int, Exception> success = Result.Ok<int, Exception>(2);
        success.Then(value => value + 1, Errors.MapAll).Should().BeOk(3);
        success.Then(value => { _ = value; }, Errors.MapAll).Should().BeOk(new Unit());
        success.Do(_ => throw new InvalidOperationException("side"), Errors.MapAll).Should().BeErr()
            .Which.Message.Should().Be("side");
        success.Assert(value => value == 2, Errors.MapAll).Should().BeOk(2);
        success.Assert(_ => false, Errors.MapAll, "assertion").Should().BeErr()
            .Which.Should().BeOfType<AssertionException>().Which.Message.Should().Be("assertion");
        new AssertionException().Message.Should().NotBeNull();
    }

    [Fact]
    public async Task It_should_capture_try_and_combine_collections()
    {
        Result.Try(() => 2).Should().BeOk(2);
        Result.Try<int>(() => throw new InvalidOperationException("bad")).Should().BeErr()
            .Which.Should().BeOfType<InvalidOperationException>();
        var escaped = () => Result.Try<int>(() => throw new InvalidOperationException(), Errors.MapNone);
        escaped.Should().Throw<InvalidOperationException>();
        (await Result.TryAsync(() => Task.FromResult(3))).Should().BeOk(3);
        (await Result.TryAsync<int>(() => Task.FromException<int>(new InvalidOperationException("async")))).Should().BeErr()
            .Which.Should().BeOfType<InvalidOperationException>();
        var asyncEscape = async () => await Result.TryAsync<int>(() => Task.FromException<int>(new InvalidOperationException()), Errors.MapNone);
        await asyncEscape.Should().ThrowAsync<InvalidOperationException>();

        Result<int, string>[] successfulResults = [Result.Ok<int, string>(1), Result.Ok<int, string>(2)];
        Result<int, string>[] mixedResults = [Result.Ok<int, string>(1), Result.Err<int, string>("a"), Result.Err<int, string>("b")];
        Task<Result<int, string>>[] asyncResults = [Task.FromResult(Result.Ok<int, string>(1)), Task.FromResult(Result.Ok<int, string>(2))];
        Result.All(successfulResults).Should().BeOk()
            .Which.Should().Equal(1, 2);
        Result.All(mixedResults).Should().BeErr()
            .Which.Should().Equal("a", "b");
        (await Result.All(asyncResults))
            .Should().BeOk();
        Result.All(Result.Ok<int, string>(1), Result.Ok<string, string>("two")).Should().BeOk((1, "two"));
        Result.All(Result.Err<int, string>("one"), Result.Err<string, string>("two")).Should().BeErr()
            .Which.Should().Equal("one", "two");
        Result.All(Result.Ok<int, string>(1), Result.Ok<string, string>("two"), Result.Ok<bool, string>(true)).Should().BeOk((1, "two", true));
        Result.All(Result.Ok<int, string>(1), Result.Err<string, string>("two"), Result.Err<bool, string>("three")).Should().BeErr()
            .Which.Should().Equal("two", "three");
    }

    [Fact]
    public void It_should_support_linq_and_collection_projections()
    {
        var results = new[] { Result.Ok<int, string>(1), Result.Err<int, string>("bad"), Result.Ok<int, string>(3) };
        results.GetSuccesses().Should().Equal(1, 3);
        results.GetFailures().Should().Equal("bad");
        results.AllSucceed().Should().BeFalse();
        results.AnySucceed().Should().BeTrue();
        new[] { Result.Err<int, string>("bad") }.AnySucceed().Should().BeFalse();
        new[] { Result.Ok<int, string>(1) }.AllSucceed().Should().BeTrue();

        var query = from left in Result.Ok<int, string>(2)
                    from right in Result.Ok<int, string>(3)
                    select left + right;
        query.Should().BeOk(5);
        Result.Err<int, string>("bad").Select(value => value * 2).Should().BeErr("bad");
    }

    [Fact]
    public void Unit_should_have_single_value_semantics()
    {
        var left = new Unit();
        var right = new Unit();
        left.Equals(right).Should().BeTrue();
        left.Equals((object)right).Should().BeTrue();
        left.Equals("unit").Should().BeFalse();
        left.GetHashCode().Should().Be(0);
        left.ToString().Should().Be("()");
        (left == right).Should().BeTrue();
        (left != right).Should().BeFalse();
    }
}
