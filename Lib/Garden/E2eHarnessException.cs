namespace AtomiCloud.Diene.E2e.Garden;

/// <summary>Reports a harness configuration that cannot identify one target safely.</summary>
/// <param name="message">The configuration failure.</param>
public sealed class E2eHarnessException(string message) : Exception(message);
