using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.Results.App;

/// <summary>
/// Exercises the full published surface of <c>AtomiCloud.Diene.Result</c> as an
/// in-repo consumer. Each method is a compilable usage example; results are
/// discarded because the demonstration is the call itself, not its output.
/// </summary>
public static class Samples
{
    /// <summary>Runs every demonstration.</summary>
    public static void RunAll()
    {
        ResultCore();
        OptionCore();
        Factories();
        Collections();
        LinqQuerySyntax();
        ExceptionChannel();
        UnwrapDiagnostics();
        AsyncRailway().GetAwaiter().GetResult();
    }

    private static void ResultCore()
    {
        var ok = Result.Ok<int, string>(21);
        var err = Result.Err<int, string>("boom");

        _ = ok.IsSuccess(out _);
        _ = err.IsFailure(out _);
        _ = ok.GetOr(0);
        _ = ok.SuccessOrDefault();
        _ = err.FailureOrDefault();
        _ = ok.Ok();
        _ = ok.ToSerial();
    }

    private static void OptionCore()
    {
        var some = Option.Some(21);
        var none = Option.None<int>();

        _ = some.IsSome(out _);
        _ = none.IsNone();
        _ = some.Map(value => value + 1);
        _ = some.Then(value => Option.Some(value + 1));
        _ = some.Match(value => value, () => 0);
        _ = none.GetOr(0);
        _ = none.GetOr(() => 0);
        _ = some.ToNullable();
        _ = some.OkOr("missing");
        _ = Option.FromNullable<string>(null);
        _ = Option.FromSerial(some.ToSerial());
    }

    private static void Factories()
    {
        var ok = Result.Ok<int, string>(21);

        _ = Result.FromSerial(ok.ToSerial());
        _ = Result.Try(() => 21);
        _ = Result.All(ok, ok);
        _ = Result.All(ok, ok, ok);
    }

    private static void Collections()
    {
        var results = new[] { Result.Ok<int, string>(21), Result.Err<int, string>("boom") };

        _ = results.GetSuccesses();
        _ = results.GetFailures();
        _ = results.AllSucceed();
        _ = results.AnySucceed();
    }

    private static void LinqQuerySyntax()
    {
        var ok = Result.Ok<int, string>(21);

        _ = from value in ok select value * 2;
        _ = from first in ok from second in ok select first + second;
    }

    private static void ExceptionChannel()
    {
        var captured = Result.Try(() => 21, Errors.MapNone);
        var filter = Errors.MapIfExceptionIs<InvalidOperationException>().Or<ArgumentException>();

        _ = captured.Then(value => value + 1, filter);
        _ = captured.Then(_ => { }, filter);
        _ = captured.Do(_ => { }, filter);
        _ = captured.Assert(value => value > 0, filter, "must be positive");
    }

    private static void UnwrapDiagnostics()
    {
        try
        {
            _ = Result.Err<int, string>("boom").Get();
        }
        catch (UnwrapException unwrap)
        {
            _ = unwrap.ExpectedVariant;
            _ = unwrap.ActualValue;
        }
    }

    private static async Task AsyncRailway()
    {
        static Task<Result<int, string>> Ok() => Task.FromResult(Result.Ok<int, string>(21));
        static Task<Result<int, string>> Err() => Task.FromResult(Result.Err<int, string>("boom"));

        _ = await Result.TryAsync(() => Task.FromResult(21));
        _ = await Result.All<int, string>([Ok(), Ok()]);
        _ = await Ok().Map(value => value + 1);
        _ = await Ok().Map(value => Task.FromResult(value + 1));
        _ = await Ok().Then(value => Result.Ok<int, string>(value));
        _ = await Ok().Then(value => Task.FromResult(Result.Ok<int, string>(value)));
        _ = await Ok().Then(value => value, Errors.MapAll, exception => exception.Message);
        _ = await Ok().Then(value => Task.FromResult(value), Errors.MapAll, exception => exception.Message);
        _ = await Err().MapFailure(error => error.ToUpperInvariant());
        _ = await Err().MapFailure(error => Task.FromResult(error.ToUpperInvariant()));
        _ = await Err().OrElse(_ => Result.Ok<int, string>(0));
        _ = await Err().OrElse(_ => Task.FromResult(Result.Ok<int, string>(0)));
        _ = await Ok().Do(_ => { });
        _ = await Ok().Do(_ => Task.CompletedTask);
        _ = await Ok().Do(_ => { }, Errors.MapAll, exception => exception.Message);
        _ = await Ok().Do(_ => Task.CompletedTask, Errors.MapAll, exception => exception.Message);
        _ = await Err().DoFailure(_ => { });
        _ = await Err().DoFailure(_ => Task.CompletedTask);
        _ = await Ok().Assert(value => Result.Ok<bool, string>(value > 0), _ => "invalid");
        _ = await Ok().Assert(value => Task.FromResult(Result.Ok<bool, string>(value > 0)), _ => "invalid");
        _ = await Ok().Assert(value => value > 0, _ => "invalid", Errors.MapAll, exception => exception.Message);
        _ = await Ok().Assert(value => Task.FromResult(value > 0), _ => "invalid", Errors.MapAll, exception => exception.Message);
        _ = await Ok().If(
            value => Result.Ok<bool, string>(value > 0),
            value => Result.Ok<int, string>(value),
            value => Result.Ok<int, string>(-value));
        _ = await Ok().If(
            value => Task.FromResult(Result.Ok<bool, string>(value > 0)),
            value => Task.FromResult(Result.Ok<int, string>(value)),
            value => Task.FromResult(Result.Ok<int, string>(-value)));
        _ = await Ok().Match(value => value, _ => -1);
        _ = await Ok().Match(value => Task.FromResult(value), _ => Task.FromResult(-1));
        _ = await Ok().Get();
        _ = await Err().GetFailure();
        _ = await Err().GetOr(_ => 0);
        _ = await Err().GetOr(_ => Task.FromResult(0));
    }
}
