namespace AtomiCloud.Diene.Results;

/// <summary>Decides whether a thrown exception is captured in a Result.</summary>
/// <param name="exception">The thrown exception.</param>
/// <returns><see langword="true"/> to capture the exception; otherwise, <see langword="false"/>.</returns>
public delegate bool ExceptionFilter(Exception exception);

/// <summary>Reusable exception-capture policies.</summary>
public static class Errors
{
    /// <summary>Captures every exception.</summary>
    public static bool MapAll(Exception _) => true;

    /// <summary>Captures no exception.</summary>
    public static bool MapNone(Exception _) => false;

    /// <summary>Captures exceptions assignable to <typeparamref name="TException"/>.</summary>
    public static ExceptionFilter MapIfExceptionIs<TException>()
        where TException : Exception => exception => exception is TException;

    /// <summary>Widens a filter to also capture <typeparamref name="TException"/>.</summary>
    public static ExceptionFilter Or<TException>(this ExceptionFilter filter)
        where TException : Exception
    {
        ArgumentNullException.ThrowIfNull(filter);
        return exception => filter(exception) || exception is TException;
    }
}
