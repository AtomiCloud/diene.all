using System.Text.Json.Serialization;
using AtomiCloud.Diene.Problems;

namespace AtomiCloud.DotnetBase.App.Error;

/// <summary>
/// A note already exists under the requested title. Identity metadata is ignored by the
/// serializer; only the typed payload reaches the wire, where it lands under <c>data</c>.
/// </summary>
/// <param name="requestedTitle">The title that collided.</param>
public sealed class NoteTitleConflict(string requestedTitle) : IDomainProblem
{
    /// <summary>
    /// Creates the empty instance the catalog uses to read metadata. The problems package
    /// requires a public parameterless constructor on every registered problem.
    /// </summary>
    public NoteTitleConflict()
        : this(string.Empty)
    {
    }

    /// <summary>The title that collided. This is the typed payload.</summary>
    public string RequestedTitle => requestedTitle;

    /// <inheritdoc />
    [JsonIgnore]
    public string Id => "note_title_conflict";

    /// <inheritdoc />
    [JsonIgnore]
    public string Title => "Note title already used";

    /// <inheritdoc />
    [JsonIgnore]
    public string Detail => $"A note titled '{this.RequestedTitle}' already exists.";

    /// <inheritdoc />
    [JsonIgnore]
    public string Version => "v1";
}
