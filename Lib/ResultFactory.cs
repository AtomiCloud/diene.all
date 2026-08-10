namespace AtomiCloud.Diene.Results;

/// <summary>Factories, exception capture, and collection composition for Results.</summary>
public static class Result
{
    /// <summary>Creates a successful Result.</summary>
    public static Result<T, E> Ok<T, E>(T value) => new(value);

    /// <summary>Creates a failed Result.</summary>
    public static Result<T, E> Err<T, E>(E error) => new(error);

    /// <summary>Creates a Result from its explicit C0 wire representation.</summary>
    public static Result<T, E> FromSerial<T, E>(ResultSerial<T, E> serial)
    {
        ArgumentNullException.ThrowIfNull(serial);
        return serial.Match(Ok<T, E>, Err<T, E>);
    }

    /// <summary>Captures matching exceptions thrown by a synchronous function.</summary>
    public static Result<T, Exception> Try<T>(Func<T> function, ExceptionFilter? filter = null)
    {
        ArgumentNullException.ThrowIfNull(function);
        filter ??= Errors.MapAll;
        try
        {
            return Ok<T, Exception>(function());
        }
        catch (Exception exception) when (filter(exception))
        {
            return Err<T, Exception>(exception);
        }
    }

    /// <summary>Captures matching exceptions thrown by an asynchronous function.</summary>
    public static async Task<Result<T, Exception>> TryAsync<T>(
        Func<Task<T>> function,
        ExceptionFilter? filter = null)
    {
        ArgumentNullException.ThrowIfNull(function);
        filter ??= Errors.MapAll;
        try
        {
            return Ok<T, Exception>(await function().ConfigureAwait(false));
        }
        catch (Exception exception) when (filter(exception))
        {
            return Err<T, Exception>(exception);
        }
    }

    /// <summary>Collects every success, or every failure when any input fails.</summary>
    public static Result<IReadOnlyList<T>, IReadOnlyList<E>> All<T, E>(IEnumerable<Result<T, E>> results)
    {
        ArgumentNullException.ThrowIfNull(results);
        var successes = new List<T>();
        var failures = new List<E>();
        foreach (var result in results)
        {
            result.Match(successes.Add, failures.Add);
        }

        return failures.Count == 0
            ? Ok<IReadOnlyList<T>, IReadOnlyList<E>>(successes)
            : Err<IReadOnlyList<T>, IReadOnlyList<E>>(failures);
    }

    /// <summary>Awaits and collects every success, or every failure when any input fails.</summary>
    public static async Task<Result<IReadOnlyList<T>, IReadOnlyList<E>>> All<T, E>(
        IEnumerable<Task<Result<T, E>>> results)
    {
        ArgumentNullException.ThrowIfNull(results);
        return All(await Task.WhenAll(results).ConfigureAwait(false));
    }

    /// <summary>Combines two heterogeneous Results and collects all failures.</summary>
    public static Result<(T1, T2), IReadOnlyList<E>> All<T1, T2, E>(Result<T1, E> first, Result<T2, E> second)
    {
        var failures = Failures(first.Err(), second.Err());
        return failures.Count == 0
            ? Ok<(T1, T2), IReadOnlyList<E>>((first.Get(), second.Get()))
            : Err<(T1, T2), IReadOnlyList<E>>(failures);
    }

    /// <summary>Combines three heterogeneous Results and collects all failures.</summary>
    public static Result<(T1, T2, T3), IReadOnlyList<E>> All<T1, T2, T3, E>(
        Result<T1, E> first,
        Result<T2, E> second,
        Result<T3, E> third)
    {
        var failures = Failures(first.Err(), second.Err(), third.Err());
        return failures.Count == 0
            ? Ok<(T1, T2, T3), IReadOnlyList<E>>((first.Get(), second.Get(), third.Get()))
            : Err<(T1, T2, T3), IReadOnlyList<E>>(failures);
    }

    private static IReadOnlyList<E> Failures<E>(params Option<E>[] options) =>
        [.. options.Where(option => option.IsSome()).Select(option => option.Get())];
}
