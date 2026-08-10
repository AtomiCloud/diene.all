using AtomiCloud.Diene.Results;
using AtomiCloud.Diene.Results.TestHelper;
using FluentAssertions;

namespace AtomiCloud.Diene.Results.UnitTest;

public class AsyncTests
{
    [Fact]
    public async Task It_should_compose_task_results_with_sync_and_async_callbacks()
    {
        var success = Task.FromResult(Result.Ok<int, string>(2));
        var failure = Task.FromResult(Result.Err<int, string>("bad"));

        (await success.Map(x => x * 2)).Should().BeOk(4);
        (await failure.Map(x => x * 2)).Should().BeErr("bad");
        (await success.Map(x => Task.FromResult(x * 3))).Should().BeOk(6);
        (await failure.Map(x => Task.FromResult(x * 3))).Should().BeErr("bad");
        (await success.Then(x => Result.Ok<int, string>(x + 1))).Should().BeOk(3);
        (await failure.Then(x => Result.Ok<int, string>(x + 1))).Should().BeErr("bad");
        (await success.Then(x => Task.FromResult(Result.Ok<int, string>(x + 2)))).Should().BeOk(4);
        (await failure.Then(x => Task.FromResult(Result.Ok<int, string>(x + 2)))).Should().BeErr("bad");
        (await success.Then(x => x + 3, Errors.MapAll, exception => exception.Message)).Should().BeOk(5);
        (await failure.Then(x => x + 3, Errors.MapAll, exception => exception.Message)).Should().BeErr("bad");
        (await success.Then(_ => Task.FromException<int>(new InvalidOperationException("async")), Errors.MapAll, exception => exception.Message))
            .Should().BeErr("async");
        (await failure.Then(x => Task.FromResult(x + 3), Errors.MapAll, exception => exception.Message)).Should().BeErr("bad");
        var escaped = async () => await success.Then(_ => Task.FromException<int>(new InvalidOperationException()), Errors.MapNone, exception => exception.Message);
        await escaped.Should().ThrowAsync<InvalidOperationException>();
    }

    [Fact]
    public async Task It_should_expose_the_full_task_extraction_surface()
    {
        var success = Task.FromResult(Result.Ok<int, string>(2));
        var failure = Task.FromResult(Result.Err<int, string>("bad"));
        var observed = "";

        (await success.MapFailure(error => error.Length)).Should().BeOk(2);
        (await failure.MapFailure(error => error.Length)).Should().BeErr(3);
        (await success.MapFailure(error => Task.FromResult(error.Length))).Should().BeOk(2);
        (await failure.MapFailure(error => Task.FromResult(error.Length))).Should().BeErr(3);
        (await success.OrElse(error => Result.Ok<int, string>(error.Length))).Should().BeOk(2);
        (await failure.OrElse(error => Result.Ok<int, string>(error.Length))).Should().BeOk(3);
        (await success.OrElse(error => Task.FromResult(Result.Ok<int, string>(error.Length)))).Should().BeOk(2);
        (await failure.OrElse(error => Task.FromResult(Result.Ok<int, string>(error.Length)))).Should().BeOk(3);
        (await success.Do(value => observed = value.ToString())).Should().BeOk(2);
        (await success.Do(value => { observed = value.ToString(); return Task.CompletedTask; })).Should().BeOk(2);
        (await failure.Do(value => { observed = value.ToString(); return Task.CompletedTask; })).Should().BeErr("bad");
        (await success.Do(value => observed = value.ToString(), Errors.MapAll, exception => exception.Message)).Should().BeOk(2);
        (await failure.DoFailure(error => observed = error)).Should().BeErr("bad");
        (await success.DoFailure(error => { observed = error; return Task.CompletedTask; })).Should().BeOk(2);
        (await failure.DoFailure(error => { observed = error; return Task.CompletedTask; })).Should().BeErr("bad");
        observed.Should().Be("bad");
        (await success.Match(value => value.ToString(), error => error)).Should().Be("2");
        (await failure.Match(value => value.ToString(), error => error)).Should().Be("bad");
        (await success.Match(value => Task.FromResult(value.ToString()), error => Task.FromResult(error))).Should().Be("2");
        (await failure.Match(value => Task.FromResult(value.ToString()), error => Task.FromResult(error))).Should().Be("bad");
        (await success.Get()).Should().Be(2);
        (await failure.GetFailure()).Should().Be("bad");
        (await success.GetOr(error => error.Length)).Should().Be(2);
        (await failure.GetOr(error => error.Length)).Should().Be(3);
        (await success.GetOr(error => Task.FromResult(error.Length))).Should().Be(2);
        (await failure.GetOr(error => Task.FromResult(error.Length))).Should().Be(3);
    }

    [Fact]
    public async Task It_should_run_filtered_async_side_effects_with_explicit_capture()
    {
        var success = Task.FromResult(Result.Ok<int, string>(2));
        var failure = Task.FromResult(Result.Err<int, string>("bad"));
        var observed = 0;

        (await success.Do(value => { observed = value; return Task.CompletedTask; }, Errors.MapAll, exception => exception.Message))
            .Should().BeOk(2);
        observed.Should().Be(2);
        (await failure.Do(value => { observed = value; return Task.CompletedTask; }, Errors.MapAll, exception => exception.Message))
            .Should().BeErr("bad");
        observed.Should().Be(2);
        (await success.Do(
            _ => Task.FromException(new InvalidOperationException("mapped")),
            Errors.MapIfExceptionIs<InvalidOperationException>(),
            exception => exception.Message)).Should().BeErr("mapped");

        var escaped = async () => await success.Do(
            _ => Task.FromException(new InvalidOperationException("escaped")),
            Errors.MapNone,
            exception => exception.Message);
        await escaped.Should().ThrowAsync<InvalidOperationException>().WithMessage("escaped");
    }

    [Fact]
    public async Task It_should_assert_task_results_without_capturing_result_callbacks()
    {
        var success = Task.FromResult(Result.Ok<int, string>(2));
        var failure = Task.FromResult(Result.Err<int, string>("bad"));
        var calls = 0;

        (await success.Assert(value => Result.Ok<bool, string>(value == 2), _ => "false")).Should().BeOk(2);
        (await success.Assert(_ => Result.Ok<bool, string>(false), _ => "false")).Should().BeErr("false");
        (await success.Assert(_ => Result.Err<bool, string>("assertion"), _ => "false")).Should().BeErr("assertion");
        (await failure.Assert(value => { calls++; return Result.Ok<bool, string>(value == 2); }, _ => "false"))
            .Should().BeErr("bad");
        calls.Should().Be(0);

        (await success.Assert(
            value => Task.FromResult(Result.Ok<bool, string>(value == 2)),
            _ => "false")).Should().BeOk(2);
        (await success.Assert(
            _ => Task.FromResult(Result.Ok<bool, string>(false)),
            _ => "false")).Should().BeErr("false");
        (await success.Assert(
            _ => Task.FromResult(Result.Err<bool, string>("assertion")),
            _ => "false")).Should().BeErr("assertion");
        (await failure.Assert(
            value => { calls++; return Task.FromResult(Result.Ok<bool, string>(value == 2)); },
            _ => "false")).Should().BeErr("bad");
        calls.Should().Be(0);

        static Result<bool, string> ThrowingResultAssertion(int _) =>
            throw new InvalidOperationException("sync escaped");
        var syncEscaped = async () => await success.Assert(ThrowingResultAssertion, _ => "false");
        await syncEscaped.Should().ThrowAsync<InvalidOperationException>().WithMessage("sync escaped");
        var asyncEscaped = async () => await success.Assert(
            _ => Task.FromException<Result<bool, string>>(new InvalidOperationException("async escaped")),
            _ => "false");
        await asyncEscaped.Should().ThrowAsync<InvalidOperationException>().WithMessage("async escaped");
    }

    [Fact]
    public async Task It_should_apply_filtered_sync_and_async_task_assertions()
    {
        var success = Task.FromResult(Result.Ok<int, string>(2));
        var failure = Task.FromResult(Result.Err<int, string>("bad"));
        var calls = 0;

        (await success.Assert(value => value == 2, _ => "false", Errors.MapAll, exception => exception.Message))
            .Should().BeOk(2);
        (await success.Assert(_ => false, _ => "false", Errors.MapAll, exception => exception.Message))
            .Should().BeErr("false");
        (await failure.Assert(value => { calls++; return value == 2; }, _ => "false", Errors.MapAll, exception => exception.Message))
            .Should().BeErr("bad");
        calls.Should().Be(0);
        static bool MappedAssertion(int _) => throw new InvalidOperationException("mapped sync");
        (await success.Assert(
            MappedAssertion,
            _ => "false",
            Errors.MapIfExceptionIs<InvalidOperationException>(),
            exception => exception.Message)).Should().BeErr("mapped sync");
        static bool EscapedAssertion(int _) => throw new InvalidOperationException("escaped sync");
        var syncEscaped = async () => await success.Assert(
            EscapedAssertion,
            _ => "false",
            Errors.MapNone,
            exception => exception.Message);
        await syncEscaped.Should().ThrowAsync<InvalidOperationException>().WithMessage("escaped sync");

        (await success.Assert(value => Task.FromResult(value == 2), _ => "false", Errors.MapAll, exception => exception.Message))
            .Should().BeOk(2);
        (await success.Assert(_ => Task.FromResult(false), _ => "false", Errors.MapAll, exception => exception.Message))
            .Should().BeErr("false");
        (await failure.Assert(
            value => { calls++; return Task.FromResult(value == 2); },
            _ => "false",
            Errors.MapAll,
            exception => exception.Message)).Should().BeErr("bad");
        calls.Should().Be(0);
        (await success.Assert(
            _ => Task.FromException<bool>(new InvalidOperationException("mapped async")),
            _ => "false",
            Errors.MapIfExceptionIs<InvalidOperationException>(),
            exception => exception.Message)).Should().BeErr("mapped async");
        var asyncEscaped = async () => await success.Assert(
            _ => Task.FromException<bool>(new InvalidOperationException("escaped async")),
            _ => "false",
            Errors.MapNone,
            exception => exception.Message);
        await asyncEscaped.Should().ThrowAsync<InvalidOperationException>().WithMessage("escaped async");
    }

    [Fact]
    public async Task It_should_branch_task_results_without_capturing_result_callbacks()
    {
        var success = Task.FromResult(Result.Ok<int, string>(2));
        var failure = Task.FromResult(Result.Err<int, string>("bad"));
        var calls = 0;

        (await success.If(
            value => Result.Ok<bool, string>(value == 2),
            value => Result.Ok<string, string>($"then {value}"),
            value => Result.Ok<string, string>($"else {value}"))).Should().BeOk("then 2");
        (await success.If(
            _ => Result.Ok<bool, string>(false),
            value => Result.Ok<string, string>($"then {value}"),
            value => Result.Ok<string, string>($"else {value}"))).Should().BeOk("else 2");
        (await success.If(
            _ => Result.Err<bool, string>("predicate"),
            value => Result.Ok<string, string>($"then {value}"),
            value => Result.Ok<string, string>($"else {value}"))).Should().BeErr("predicate");
        (await failure.If(
            value => { calls++; return Result.Ok<bool, string>(value == 2); },
            value => Result.Ok<string, string>($"then {value}"),
            value => Result.Ok<string, string>($"else {value}"))).Should().BeErr("bad");
        calls.Should().Be(0);

        (await success.If(
            value => Task.FromResult(Result.Ok<bool, string>(value == 2)),
            value => Task.FromResult(Result.Ok<string, string>($"then {value}")),
            value => Task.FromResult(Result.Ok<string, string>($"else {value}")))).Should().BeOk("then 2");
        (await success.If(
            _ => Task.FromResult(Result.Ok<bool, string>(false)),
            value => Task.FromResult(Result.Ok<string, string>($"then {value}")),
            value => Task.FromResult(Result.Ok<string, string>($"else {value}")))).Should().BeOk("else 2");
        (await success.If(
            _ => Task.FromResult(Result.Err<bool, string>("predicate")),
            value => Task.FromResult(Result.Ok<string, string>($"then {value}")),
            value => Task.FromResult(Result.Ok<string, string>($"else {value}")))).Should().BeErr("predicate");
        (await failure.If(
            value => { calls++; return Task.FromResult(Result.Ok<bool, string>(value == 2)); },
            value => Task.FromResult(Result.Ok<string, string>($"then {value}")),
            value => Task.FromResult(Result.Ok<string, string>($"else {value}")))).Should().BeErr("bad");
        calls.Should().Be(0);

        var syncEscaped = async () => await success.If<int, string, string>(
            _ => throw new InvalidOperationException("sync escaped"),
            value => Result.Ok<string, string>($"then {value}"),
            value => Result.Ok<string, string>($"else {value}"));
        await syncEscaped.Should().ThrowAsync<InvalidOperationException>().WithMessage("sync escaped");
        var asyncEscaped = async () => await success.If(
            _ => Task.FromException<Result<bool, string>>(new InvalidOperationException("async escaped")),
            value => Task.FromResult(Result.Ok<string, string>($"then {value}")),
            value => Task.FromResult(Result.Ok<string, string>($"else {value}")));
        await asyncEscaped.Should().ThrowAsync<InvalidOperationException>().WithMessage("async escaped");
    }
}
