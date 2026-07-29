namespace AtomiCloud.Diene.E2e.TestHelper.Assertions;

/// <summary>Reports a black-box response that violated the expected contract.</summary>
/// <param name="message">The assertion failure.</param>
public sealed class E2eAssertionException(string message) : Exception(message);
