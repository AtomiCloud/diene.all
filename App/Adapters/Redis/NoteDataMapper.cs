using AtomiCloud.Diene.Note;

namespace AtomiCloud.DotnetBase.App.Adapters.Redis;

/// <summary>Maps between Redis storage data and the domain note representation.</summary>
internal static class NoteDataMapper
{
    public static NoteData ToData(this NotePrincipal principal) => new()
    {
        Id = principal.Id,
        Title = principal.Record.Title,
        Body = principal.Record.Body,
    };

    public static NotePrincipal ToDomain(this NoteData data) => new()
    {
        Id = data.Id,
        Record = new NoteRecord { Title = data.Title, Body = data.Body },
    };
}
