namespace AtomiCloud.DotnetBase.Lib.Note;

/// <summary>A persisted note: stable identity paired with its content.</summary>
public record NotePrincipal
{
    public required string Id { get; init; }

    public required NoteRecord Record { get; init; }
}
