using AtomiCloud.DotnetBase.Lib.Note;

namespace AtomiCloud.DotnetBase.App.Adapters.Postgres;

/// <summary>
/// Relational storage model, kept separate from the domain note so a schema change is not a
/// domain change.
/// </summary>
public sealed class NoteEntity
{
    /// <summary>Stable identity.</summary>
    public string Id { get; set; } = string.Empty;

    /// <summary>Note title. Unique — a collision is the domain's <c>note_title_conflict</c>.</summary>
    public string Title { get; set; } = string.Empty;

    /// <summary>Note body.</summary>
    public string Body { get; set; } = string.Empty;
}

/// <summary>Maps between relational storage rows and the domain note representation.</summary>
public static class NoteEntityMapper
{
    /// <summary>Projects a domain principal onto its storage row.</summary>
    /// <param name="principal">The domain value.</param>
    /// <returns>The storage row.</returns>
    public static NoteEntity ToEntity(this NotePrincipal principal)
    {
        ArgumentNullException.ThrowIfNull(principal);
        return new NoteEntity
        {
            Id = principal.Id,
            Title = principal.Record.Title,
            Body = principal.Record.Body,
        };
    }

    /// <summary>Projects a storage row back onto the domain principal.</summary>
    /// <param name="entity">The storage row.</param>
    /// <returns>The domain value.</returns>
    public static NotePrincipal ToDomain(this NoteEntity entity)
    {
        ArgumentNullException.ThrowIfNull(entity);
        return new NotePrincipal
        {
            Id = entity.Id,
            Record = new NoteRecord { Title = entity.Title, Body = entity.Body },
        };
    }
}
