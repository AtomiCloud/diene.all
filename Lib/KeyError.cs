namespace AtomiCloud.Diene.CoreUtils;

/// <summary>
/// A key or namespace that could not be turned into a stable identifier.
/// Total functions in this library return this instead of throwing, so a caller
/// composing keys from user input never has to guard with try/catch.
/// </summary>
/// <param name="Reason">Why the part was rejected.</param>
/// <param name="Offending">The part as the caller supplied it.</param>
public sealed record KeyError(string Reason, string Offending);
