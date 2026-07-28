namespace AtomiCloud.Diene.Note;

/// <summary>Produces a short, single-line preview of a note.</summary>
public interface INoteSummariser
{
    string Summarise(NoteRecord record, int maxLength);
}
