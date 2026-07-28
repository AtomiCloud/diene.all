namespace AtomiCloud.Diene.ApiEngine.Calls;

/// <summary>
/// What a failed exchange left behind: whatever status, media type, and body actually
/// arrived. Every field is optional because HTTP genuinely permits a failure to carry none
/// of them.
/// </summary>
internal sealed record ApiFailure(int? Status, string? ContentType, string? Body);
