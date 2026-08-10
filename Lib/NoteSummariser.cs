namespace AtomiCloud.Diene.Note;

/// <summary>Pure, deterministic note preview formatter.</summary>
public class NoteSummariser : INoteSummariser
{
    private const string Ellipsis = "…";
    private const string Separator = " — ";

    public string Summarise(NoteRecord record, int maxLength)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maxLength);

        var parts = new[] { record.Title, record.Body }
            .Select(part => string.Join(
                ' ',
                part.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)))
            .Where(part => part.Length > 0)
            .ToArray();

        var collapsed = string.Join(Separator, parts);
        if (collapsed.Length <= maxLength) return collapsed;

        var budget = maxLength - Ellipsis.Length;
        var window = collapsed[..budget];
        var lastSpace = window.LastIndexOf(' ');
        var clipped = (lastSpace > 0 ? window[..lastSpace] : window).TrimEnd();

        if (clipped.Length > 0 && char.IsHighSurrogate(clipped[^1]))
            clipped = clipped[..^1].TrimEnd();

        if (parts.Length == 2 && clipped.Length > parts[0].Length)
        {
            var bodyStart = parts[0].Length + Separator.Length;
            var survivingBody = clipped.Length > bodyStart ? clipped[bodyStart..] : string.Empty;
            if (survivingBody.All(c => c is '—' or ' '))
                clipped = parts[0];
        }

        return clipped + Ellipsis;
    }
}
