namespace AtomiCloud.Diene.Note;

/// <summary>Persistence boundary owned by the note domain.</summary>
public interface INoteRepository
{
    Task<NotePrincipal> Save(NoteRecord record, CancellationToken cancellationToken = default);

    Task<NotePrincipal?> Find(string id, CancellationToken cancellationToken = default);
}
