namespace AtomiCloud.Diene.Results;

/// <summary>Carboxylic-shaped overloads for Results whose error channel is Exception.</summary>
public static class ExceptionResultExtensions
{
    /// <summary>Chains a raw continuation and places captured exceptions directly in the error channel.</summary>
    public static Result<TOut, Exception> Then<T, TOut>(
        this Result<T, Exception> result,
        Func<T, TOut> continuation,
        ExceptionFilter filter) =>
        result.Then(continuation, filter, exception => exception);

    /// <summary>Runs a raw continuation and maps success to Unit.</summary>
    public static Result<Unit, Exception> Then<T>(
        this Result<T, Exception> result,
        Action<T> continuation,
        ExceptionFilter filter) =>
        result.Then(continuation, filter, exception => exception);

    /// <summary>Runs a success-side effect with captured exceptions placed directly in the error channel.</summary>
    public static Result<T, Exception> Do<T>(
        this Result<T, Exception> result,
        Action<T> sideEffect,
        ExceptionFilter filter) =>
        result.Do(sideEffect, filter, exception => exception);

    /// <summary>Requires a raw assertion and represents a false result as <see cref="AssertionException"/>.</summary>
    public static Result<T, Exception> Assert<T>(
        this Result<T, Exception> result,
        Func<T, bool> assertion,
        ExceptionFilter filter,
        string? message = null) =>
        result.Assert(assertion, _ => new AssertionException(message), filter, exception => exception);
}
