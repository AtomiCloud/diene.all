namespace AtomiCloud.Diene.AuthEngine.TestHelper.Assertions;

/// <summary>
/// Raised when an auth assertion does not hold. A dedicated type keeps an assertion
/// failure distinguishable from a genuine error thrown by the code under test, which
/// otherwise both surface as a failing test for different reasons.
/// </summary>
public sealed class AuthAssertionException : Exception
{
    /// <summary>Creates the exception with an explanatory message.</summary>
    public AuthAssertionException(string message)
        : base(message)
    {
    }

    /// <summary>Creates the exception with a message and an underlying cause.</summary>
    public AuthAssertionException(string message, Exception innerException)
        : base(message, innerException)
    {
    }

    /// <summary>Creates the exception with no message.</summary>
    public AuthAssertionException()
    {
    }
}
