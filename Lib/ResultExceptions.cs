namespace AtomiCloud.Diene.Results;

/// <summary>Thrown when a default-initialized Result or Option is observed.</summary>
public sealed class InvalidResultException : InvalidOperationException
{
    /// <summary>Initializes the exception.</summary>
    public InvalidResultException()
        : base("A default-initialized Result or Option has no variant.") { }
}

/// <summary>Thrown when the wrong Result or Option variant is extracted.</summary>
public sealed class UnwrapException(string expectedVariant, object? actualValue)
    : InvalidOperationException($"Expected {expectedVariant}, but the other variant was present.")
{
    /// <summary>Gets the expected variant name.</summary>
    public string ExpectedVariant { get; } = expectedVariant;

    /// <summary>Gets the value carried by the actual variant.</summary>
    public object? ActualValue { get; } = actualValue;
}

/// <summary>A captured assertion failure for exception-typed Results.</summary>
public sealed class AssertionException(string? message = null) : Exception(message)
{
}
