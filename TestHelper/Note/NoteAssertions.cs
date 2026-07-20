namespace AtomiCloud.Diene.Note.TestHelper.Note;

/// <summary>Assertions for the public note-domain surface.</summary>
public static class NoteAssertions
{
    public static void AssertSummary(this INoteSummariser subject, NoteRecord record, int maxLength, string expected)
    {
        ArgumentNullException.ThrowIfNull(subject);
        ArgumentNullException.ThrowIfNull(record);

        var actual = subject.Summarise(record, maxLength);
        if (!string.Equals(actual, expected, StringComparison.Ordinal))
            throw new InvalidOperationException($"Expected summary '{expected}' but found '{actual}'.");
    }
}
