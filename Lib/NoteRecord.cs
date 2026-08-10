namespace AtomiCloud.Diene.Note;

/// <summary>The immutable content of a note, without identity.</summary>
public record NoteRecord
{
    public required string Title { get; init; }

    public required string Body { get; init; }
}
