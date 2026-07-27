namespace AtomiCloud.Diene.Results;

/// <summary>Railway composition over <see cref="Task{TResult}"/> of Result.</summary>
public static class ResultTaskExtensions
{
    /// <summary>Maps a successful value with a synchronous callback.</summary>
    public static async Task<Result<TOut, E>> Map<T, TOut, E>(this Task<Result<T, E>> task, Func<T, TOut> mapper) =>
        (await task.ConfigureAwait(false)).Map(mapper);

    /// <summary>Maps a successful value with an asynchronous callback.</summary>
    public static async Task<Result<TOut, E>> Map<T, TOut, E>(this Task<Result<T, E>> task, Func<T, Task<TOut>> mapper)
    {
        ArgumentNullException.ThrowIfNull(mapper);
        var result = await task.ConfigureAwait(false);
        return result.IsSuccess()
            ? Result.Ok<TOut, E>(await mapper(result.Get()).ConfigureAwait(false))
            : Result.Err<TOut, E>(result.GetFailure());
    }

    /// <summary>Chains a synchronous Result-returning callback.</summary>
    public static async Task<Result<TOut, E>> Then<T, TOut, E>(
        this Task<Result<T, E>> task,
        Func<T, Result<TOut, E>> continuation) =>
        (await task.ConfigureAwait(false)).Then(continuation);

    /// <summary>Chains an asynchronous Result-returning callback.</summary>
    public static async Task<Result<TOut, E>> Then<T, TOut, E>(
        this Task<Result<T, E>> task,
        Func<T, Task<Result<TOut, E>>> continuation)
    {
        ArgumentNullException.ThrowIfNull(continuation);
        var result = await task.ConfigureAwait(false);
        return result.IsSuccess()
            ? await continuation(result.Get()).ConfigureAwait(false)
            : Result.Err<TOut, E>(result.GetFailure());
    }

    /// <summary>Chains a raw synchronous callback with an explicit capture policy.</summary>
    public static async Task<Result<TOut, E>> Then<T, TOut, E>(
        this Task<Result<T, E>> task,
        Func<T, TOut> continuation,
        ExceptionFilter filter,
        Func<Exception, E> errorMapper) =>
        (await task.ConfigureAwait(false)).Then(continuation, filter, errorMapper);

    /// <summary>Chains a raw asynchronous callback with an explicit capture policy.</summary>
    public static async Task<Result<TOut, E>> Then<T, TOut, E>(
        this Task<Result<T, E>> task,
        Func<T, Task<TOut>> continuation,
        ExceptionFilter filter,
        Func<Exception, E> errorMapper)
    {
        ArgumentNullException.ThrowIfNull(continuation);
        ArgumentNullException.ThrowIfNull(filter);
        ArgumentNullException.ThrowIfNull(errorMapper);
        var result = await task.ConfigureAwait(false);
        if (result.IsFailure()) return Result.Err<TOut, E>(result.GetFailure());
        try
        {
            return Result.Ok<TOut, E>(await continuation(result.Get()).ConfigureAwait(false));
        }
        catch (Exception exception) when (filter(exception))
        {
            return Result.Err<TOut, E>(errorMapper(exception));
        }
    }

    /// <summary>Maps a failure value.</summary>
    public static async Task<Result<T, EOut>> MapFailure<T, E, EOut>(
        this Task<Result<T, E>> task,
        Func<E, EOut> mapper) =>
        (await task.ConfigureAwait(false)).MapFailure(mapper);

    /// <summary>Maps a failure value with an asynchronous callback.</summary>
    public static async Task<Result<T, EOut>> MapFailure<T, E, EOut>(
        this Task<Result<T, E>> task,
        Func<E, Task<EOut>> mapper)
    {
        ArgumentNullException.ThrowIfNull(mapper);
        var result = await task.ConfigureAwait(false);
        return result.IsFailure()
            ? Result.Err<T, EOut>(await mapper(result.GetFailure()).ConfigureAwait(false))
            : Result.Ok<T, EOut>(result.Get());
    }

    /// <summary>Recovers from a failure.</summary>
    public static async Task<Result<T, E>> OrElse<T, E>(
        this Task<Result<T, E>> task,
        Func<E, Result<T, E>> continuation) =>
        (await task.ConfigureAwait(false)).OrElse(continuation);

    /// <summary>Recovers from a failure with an asynchronous callback.</summary>
    public static async Task<Result<T, E>> OrElse<T, E>(
        this Task<Result<T, E>> task,
        Func<E, Task<Result<T, E>>> continuation)
    {
        ArgumentNullException.ThrowIfNull(continuation);
        var result = await task.ConfigureAwait(false);
        return result.IsFailure() ? await continuation(result.GetFailure()).ConfigureAwait(false) : result;
    }

    /// <summary>Runs a success-side effect.</summary>
    public static async Task<Result<T, E>> Do<T, E>(this Task<Result<T, E>> task, Action<T> sideEffect) =>
        (await task.ConfigureAwait(false)).Do(sideEffect);

    /// <summary>Runs an asynchronous success-side effect.</summary>
    public static async Task<Result<T, E>> Do<T, E>(
        this Task<Result<T, E>> task,
        Func<T, Task> sideEffect)
    {
        ArgumentNullException.ThrowIfNull(sideEffect);
        var result = await task.ConfigureAwait(false);
        if (result.IsSuccess()) await sideEffect(result.Get()).ConfigureAwait(false);
        return result;
    }

    /// <summary>Runs a filtered synchronous success-side effect.</summary>
    public static async Task<Result<T, E>> Do<T, E>(
        this Task<Result<T, E>> task,
        Action<T> sideEffect,
        ExceptionFilter filter,
        Func<Exception, E> errorMapper) =>
        (await task.ConfigureAwait(false)).Do(sideEffect, filter, errorMapper);

    /// <summary>Runs a filtered asynchronous success-side effect.</summary>
    public static async Task<Result<T, E>> Do<T, E>(
        this Task<Result<T, E>> task,
        Func<T, Task> sideEffect,
        ExceptionFilter filter,
        Func<Exception, E> errorMapper)
    {
        ArgumentNullException.ThrowIfNull(sideEffect);
        ArgumentNullException.ThrowIfNull(filter);
        ArgumentNullException.ThrowIfNull(errorMapper);
        var result = await task.ConfigureAwait(false);
        if (result.IsFailure()) return result;

        try
        {
            await sideEffect(result.Get()).ConfigureAwait(false);
            return result;
        }
        catch (Exception exception) when (filter(exception))
        {
            return Result.Err<T, E>(errorMapper(exception));
        }
    }

    /// <summary>Runs a failure-side effect.</summary>
    public static async Task<Result<T, E>> DoFailure<T, E>(this Task<Result<T, E>> task, Action<E> sideEffect) =>
        (await task.ConfigureAwait(false)).DoFailure(sideEffect);

    /// <summary>Runs an asynchronous failure-side effect.</summary>
    public static async Task<Result<T, E>> DoFailure<T, E>(
        this Task<Result<T, E>> task,
        Func<E, Task> sideEffect)
    {
        ArgumentNullException.ThrowIfNull(sideEffect);
        var result = await task.ConfigureAwait(false);
        if (result.IsFailure()) await sideEffect(result.GetFailure()).ConfigureAwait(false);
        return result;
    }

    /// <summary>Requires a synchronous Result-returning assertion to succeed.</summary>
    public static async Task<Result<T, E>> Assert<T, E>(
        this Task<Result<T, E>> task,
        Func<T, Result<bool, E>> assertion,
        Func<T, E> failure) =>
        (await task.ConfigureAwait(false)).Assert(assertion, failure);

    /// <summary>Requires an asynchronous Result-returning assertion to succeed.</summary>
    public static async Task<Result<T, E>> Assert<T, E>(
        this Task<Result<T, E>> task,
        Func<T, Task<Result<bool, E>>> assertion,
        Func<T, E> failure)
    {
        ArgumentNullException.ThrowIfNull(assertion);
        ArgumentNullException.ThrowIfNull(failure);
        var result = await task.ConfigureAwait(false);
        if (result.IsFailure()) return result;
        var value = result.Get();
        var checkedResult = await assertion(value).ConfigureAwait(false);
        return checkedResult.Match(
            passed => passed ? result : Result.Err<T, E>(failure(value)),
            error => Result.Err<T, E>(error));
    }

    /// <summary>Requires a raw synchronous assertion with an explicit exception-capture policy.</summary>
    public static async Task<Result<T, E>> Assert<T, E>(
        this Task<Result<T, E>> task,
        Func<T, bool> assertion,
        Func<T, E> failure,
        ExceptionFilter filter,
        Func<Exception, E> errorMapper) =>
        (await task.ConfigureAwait(false)).Assert(assertion, failure, filter, errorMapper);

    /// <summary>Requires a raw asynchronous assertion with an explicit exception-capture policy.</summary>
    public static async Task<Result<T, E>> Assert<T, E>(
        this Task<Result<T, E>> task,
        Func<T, Task<bool>> assertion,
        Func<T, E> failure,
        ExceptionFilter filter,
        Func<Exception, E> errorMapper)
    {
        ArgumentNullException.ThrowIfNull(assertion);
        ArgumentNullException.ThrowIfNull(failure);
        ArgumentNullException.ThrowIfNull(filter);
        ArgumentNullException.ThrowIfNull(errorMapper);
        var result = await task.ConfigureAwait(false);
        if (result.IsFailure()) return result;
        var value = result.Get();

        try
        {
            return await assertion(value).ConfigureAwait(false)
                ? result
                : Result.Err<T, E>(failure(value));
        }
        catch (Exception exception) when (filter(exception))
        {
            return Result.Err<T, E>(errorMapper(exception));
        }
    }

    /// <summary>Branches to one of two synchronous Result-returning continuations.</summary>
    public static async Task<Result<TOut, E>> If<T, TOut, E>(
        this Task<Result<T, E>> task,
        Func<T, Result<bool, E>> predicate,
        Func<T, Result<TOut, E>> then,
        Func<T, Result<TOut, E>> otherwise) =>
        (await task.ConfigureAwait(false)).If(predicate, then, otherwise);

    /// <summary>Branches to one of two asynchronous Result-returning continuations.</summary>
    public static async Task<Result<TOut, E>> If<T, TOut, E>(
        this Task<Result<T, E>> task,
        Func<T, Task<Result<bool, E>>> predicate,
        Func<T, Task<Result<TOut, E>>> then,
        Func<T, Task<Result<TOut, E>>> otherwise)
    {
        ArgumentNullException.ThrowIfNull(predicate);
        ArgumentNullException.ThrowIfNull(then);
        ArgumentNullException.ThrowIfNull(otherwise);
        var result = await task.ConfigureAwait(false);
        if (result.IsFailure()) return Result.Err<TOut, E>(result.GetFailure());
        var value = result.Get();
        var checkedResult = await predicate(value).ConfigureAwait(false);
        if (checkedResult.IsFailure()) return Result.Err<TOut, E>(checkedResult.GetFailure());
        return checkedResult.Get()
            ? await then(value).ConfigureAwait(false)
            : await otherwise(value).ConfigureAwait(false);
    }

    /// <summary>Exhaustively maps either variant.</summary>
    public static async Task<TOut> Match<T, TOut, E>(
        this Task<Result<T, E>> task,
        Func<T, TOut> success,
        Func<E, TOut> failure) =>
        (await task.ConfigureAwait(false)).Match(success, failure);

    /// <summary>Exhaustively maps either variant with asynchronous callbacks.</summary>
    public static async Task<TOut> Match<T, TOut, E>(
        this Task<Result<T, E>> task,
        Func<T, Task<TOut>> success,
        Func<E, Task<TOut>> failure)
    {
        ArgumentNullException.ThrowIfNull(success);
        ArgumentNullException.ThrowIfNull(failure);
        var result = await task.ConfigureAwait(false);
        return result.IsSuccess()
            ? await success(result.Get()).ConfigureAwait(false)
            : await failure(result.GetFailure()).ConfigureAwait(false);
    }

    /// <summary>Gets the success value.</summary>
    public static async Task<T> Get<T, E>(this Task<Result<T, E>> task) =>
        (await task.ConfigureAwait(false)).Get();

    /// <summary>Gets the failure value.</summary>
    public static async Task<E> GetFailure<T, E>(this Task<Result<T, E>> task) =>
        (await task.ConfigureAwait(false)).GetFailure();

    /// <summary>Gets the success value or computes a fallback.</summary>
    public static async Task<T> GetOr<T, E>(this Task<Result<T, E>> task, Func<E, T> fallback) =>
        (await task.ConfigureAwait(false)).GetOr(fallback);

    /// <summary>Gets the success value or computes an asynchronous fallback.</summary>
    public static async Task<T> GetOr<T, E>(this Task<Result<T, E>> task, Func<E, Task<T>> fallback)
    {
        ArgumentNullException.ThrowIfNull(fallback);
        var result = await task.ConfigureAwait(false);
        return result.IsSuccess() ? result.Get() : await fallback(result.GetFailure()).ConfigureAwait(false);
    }
}
