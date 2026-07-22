namespace AtomiCloud.Diene.Results;

/// <summary>Common projections over homogeneous Result collections.</summary>
public static class ResultCollectionExtensions
{
    /// <summary>Gets all success values.</summary>
    public static IEnumerable<T> GetSuccesses<T, E>(this IEnumerable<Result<T, E>> results)
    {
        ArgumentNullException.ThrowIfNull(results);
        return results.Where(result => result.IsSuccess()).Select(result => result.Get());
    }

    /// <summary>Gets all failure values.</summary>
    public static IEnumerable<E> GetFailures<T, E>(this IEnumerable<Result<T, E>> results)
    {
        ArgumentNullException.ThrowIfNull(results);
        return results.Where(result => result.IsFailure()).Select(result => result.GetFailure());
    }

    /// <summary>Returns whether every Result succeeds.</summary>
    public static bool AllSucceed<T, E>(this IEnumerable<Result<T, E>> results)
    {
        ArgumentNullException.ThrowIfNull(results);
        return results.All(result => result.IsSuccess());
    }

    /// <summary>Returns whether any Result succeeds.</summary>
    public static bool AnySucceed<T, E>(this IEnumerable<Result<T, E>> results)
    {
        ArgumentNullException.ThrowIfNull(results);
        return results.Any(result => result.IsSuccess());
    }
}
