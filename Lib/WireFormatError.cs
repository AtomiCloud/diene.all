namespace AtomiCloud.Diene.CoreUtils;

/// <summary>
/// A wire payload that does not obey the C0 §1 serialization contract.
/// Parsing is total: every codec in <see cref="Wire" /> reports a rejection with
/// this record rather than throwing.
/// </summary>
/// <param name="Expected">The canonical form the codec required.</param>
/// <param name="Actual">The payload as it arrived.</param>
public sealed record WireFormatError(string Expected, string Actual);
