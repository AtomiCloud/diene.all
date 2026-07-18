namespace AtomiCloud.DotnetBase.App.Adapters.Redis;

/// <summary>Storage model kept separate from the domain note representation.</summary>
internal sealed record NoteData
{
    public required string Id { get; init; }

    public required string Title { get; init; }

    public required string Body { get; init; }
}
