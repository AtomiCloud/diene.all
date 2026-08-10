using System.Net.Http.Json;
using AtomiCloud.Diene.CoreUtils.Json;

namespace AtomiCloud.DotnetBase.App;

/// <summary>
/// A generated-client stand-in: constructed over an <see cref="HttpClient" />, returning typed
/// values and throwing on anything else.
/// </summary>
/// <remarks>
/// This is the minimal structural contract a generated SDK must satisfy for the engine to wrap
/// it — take an <c>HttpClient</c>, return <c>Task&lt;T&gt;</c>, throw on failure. Kiota output
/// satisfies it, which is why the engine needs no dependency on Kiota's abstractions and no
/// reflection over generated exception types. Hand-written here so the demo has no code
/// generator in its build.
/// </remarks>
/// <param name="http">The configured client the tree supplies.</param>
public sealed class NotesClient(HttpClient http)
{
    private readonly HttpClient _http = http ?? throw new ArgumentNullException(nameof(http));

    /// <summary>Reads a note, throwing exactly as a generated client would on any failure.</summary>
    public async Task<NoteView> GetAsync(string path, CancellationToken cancellationToken = default)
    {
        using var response = await _http.GetAsync(path, cancellationToken).ConfigureAwait(false);
        response.EnsureSuccessStatusCode();
        return await response.Content
                   .ReadFromJsonAsync<NoteView>(AtomiJson.DefaultOptions, cancellationToken)
                   .ConfigureAwait(false)
               ?? throw new InvalidOperationException($"Upstream returned an empty body for '{path}'.");
    }

    /// <summary>Issues a call whose success carries no value.</summary>
    public async Task PingAsync(string path, CancellationToken cancellationToken = default)
    {
        using var response = await _http.GetAsync(path, cancellationToken).ConfigureAwait(false);
        response.EnsureSuccessStatusCode();
    }
}
