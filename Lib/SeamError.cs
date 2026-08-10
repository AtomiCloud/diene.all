using System.Collections.Immutable;

namespace AtomiCloud.Diene.Interfaces;

/// <summary>Identifies which shared seam produced a value or an error.</summary>
public enum SeamKind
{
    /// <summary>The process, environment, and clock seam.</summary>
    System,

    /// <summary>The virtual filesystem seam.</summary>
    Vfs,

    /// <summary>The process-execution seam.</summary>
    Terminal,

    /// <summary>The structured-logging emit seam.</summary>
    Logging,

    /// <summary>The metrics emit seam.</summary>
    Metrics,
}

/// <summary>
/// The failure channel of every seam. Seam methods return
/// <c>Result&lt;T, SeamError&gt;</c> instead of throwing, so a
/// <see cref="SeamError"/> is a value, never an exception.
/// </summary>
public sealed class SeamError : IEquatable<SeamError>
{
    private readonly ImmutableSortedDictionary<string, string> _data;

    /// <summary>Creates a seam error.</summary>
    /// <param name="seam">The seam that failed.</param>
    /// <param name="id">The stable machine-readable failure id.</param>
    /// <param name="title">The short human-readable failure title.</param>
    /// <param name="detail">The human-readable failure detail.</param>
    /// <param name="data">Optional structured context copied into the error.</param>
    public SeamError(
        SeamKind seam,
        string id,
        string title,
        string detail,
        IEnumerable<KeyValuePair<string, string>>? data = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(id);
        ArgumentNullException.ThrowIfNull(title);
        ArgumentNullException.ThrowIfNull(detail);
        Seam = seam;
        Id = id;
        Title = title;
        Detail = detail;
        _data = data is null
            ? ImmutableSortedDictionary<string, string>.Empty
            : ImmutableSortedDictionary.CreateRange(StringComparer.Ordinal, data);
    }

    /// <summary>The seam that failed.</summary>
    public SeamKind Seam { get; }

    /// <summary>The stable machine-readable failure id.</summary>
    public string Id { get; }

    /// <summary>The short human-readable failure title.</summary>
    public string Title { get; }

    /// <summary>The human-readable failure detail.</summary>
    public string Detail { get; }

    /// <summary>Structured context, ordered by key.</summary>
    public IReadOnlyDictionary<string, string> Data => _data;

    /// <summary>Returns a copy carrying one additional context entry.</summary>
    public SeamError With(string key, string value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(key);
        ArgumentNullException.ThrowIfNull(value);
        return new SeamError(Seam, Id, Title, Detail, _data.SetItem(key, value));
    }

    /// <inheritdoc />
    public bool Equals(SeamError? other) =>
        other is not null &&
        Seam == other.Seam &&
        string.Equals(Id, other.Id, StringComparison.Ordinal) &&
        string.Equals(Title, other.Title, StringComparison.Ordinal) &&
        string.Equals(Detail, other.Detail, StringComparison.Ordinal) &&
        _data.Count == other._data.Count &&
        _data.SequenceEqual(other._data);

    /// <inheritdoc />
    public override bool Equals(object? obj) => Equals(obj as SeamError);

    /// <inheritdoc />
    public override int GetHashCode() => HashCode.Combine(Seam, Id, Title, Detail, _data.Count);

    /// <summary>Renders the error as <c>seam/id: detail</c>.</summary>
    public override string ToString() => $"{SeamWire.Name(Seam)}/{Id}: {Detail}";

    /// <summary>Determines whether two seam errors are equal.</summary>
    public static bool operator ==(SeamError? left, SeamError? right) =>
        left is null ? right is null : left.Equals(right);

    /// <summary>Determines whether two seam errors are unequal.</summary>
    public static bool operator !=(SeamError? left, SeamError? right) => !(left == right);
}
