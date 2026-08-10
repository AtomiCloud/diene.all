namespace AtomiCloud.Diene.Results;

/// <summary>LINQ query syntax for Results.</summary>
public static class ResultLinqExtensions
{
    /// <summary>Maps a Result for LINQ <c>select</c>.</summary>
    public static Result<TOut, E> Select<T, TOut, E>(this Result<T, E> result, Func<T, TOut> mapper) => result.Map(mapper);

    /// <summary>Chains and projects Results for LINQ <c>from</c>.</summary>
    public static Result<TOut, E> SelectMany<T, TMiddle, TOut, E>(
        this Result<T, E> result,
        Func<T, Result<TMiddle, E>> continuation,
        Func<T, TMiddle, TOut> projector) =>
        result.Then(value => continuation(value).Map(middle => projector(value, middle)));
}
