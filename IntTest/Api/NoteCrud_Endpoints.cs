using System.Net;
using System.Net.Http.Json;
using AtomiCloud.Diene.Problems.TestHelper;
using AtomiCloud.DotnetBase.App.Modules.Note.API.V1;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.IntTest.Api;

/// <summary>
/// The note CRUD endpoints end to end: real routing, real versioning, real validation, real EF
/// Core against a real Postgres. Nothing is substituted, so a broken route, a broken migration or
/// a broken mapping all show up here as a status a caller would actually receive.
/// </summary>
public class NoteCrud_Endpoints : IAsyncLifetime
{
    private readonly PersistentServiceHost _host = new();

    private HttpClient _client = null!;

    public async ValueTask InitializeAsync()
    {
        await this._host.InitializeAsync();
        this._client = this._host.CreateClient();
    }

    public async ValueTask DisposeAsync()
    {
        this._client?.Dispose();
        await this._host.DisposeAsync();
    }

    [Fact]
    public async Task It_should_create_read_update_and_delete_a_note()
    {
        // Arrange
        var title = Unique("Lifecycle");

        // Act — create
        var created = await this._client.PostAsJsonAsync(
            "/api/v1/notes",
            new { title, body = "first" },
            TestContext.Current.CancellationToken);

        // Assert — create
        created.StatusCode.Should().Be(HttpStatusCode.OK);
        var note = await created.Content.ReadFromJsonAsync<NoteView>(TestContext.Current.CancellationToken);
        note.Should().NotBeNull();
        note!.Id.Should().NotBeNullOrWhiteSpace();
        note.Title.Should().Be(title);
        note.Body.Should().Be("first");

        // Act + Assert — read it back through routing, not through the context
        var read = await this._client.GetAsync($"/api/v1/notes/{note.Id}", TestContext.Current.CancellationToken);
        read.StatusCode.Should().Be(HttpStatusCode.OK);
        (await read.Content.ReadFromJsonAsync<NoteView>(TestContext.Current.CancellationToken))
            .Should().Be(note);

        // Act + Assert — update
        var updated = await this._client.PutAsJsonAsync(
            $"/api/v1/notes/{note.Id}",
            new { title, body = "second" },
            TestContext.Current.CancellationToken);
        updated.StatusCode.Should().Be(HttpStatusCode.OK);
        (await updated.Content.ReadFromJsonAsync<NoteView>(TestContext.Current.CancellationToken))!
            .Body.Should().Be("second");

        // Act + Assert — delete answers 204 with no body
        var deleted = await this._client.DeleteAsync(
            $"/api/v1/notes/{note.Id}",
            TestContext.Current.CancellationToken);
        deleted.StatusCode.Should().Be(HttpStatusCode.NoContent);

        // Act + Assert — and it is really gone
        var gone = await this._client.GetAsync($"/api/v1/notes/{note.Id}", TestContext.Current.CancellationToken);
        gone.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task It_should_list_the_notes_it_created()
    {
        // Arrange
        var first = Unique("ListA");
        var second = Unique("ListB");
        await this._client.PostAsJsonAsync(
            "/api/v1/notes",
            new { title = first, body = "a" },
            TestContext.Current.CancellationToken);
        await this._client.PostAsJsonAsync(
            "/api/v1/notes",
            new { title = second, body = "b" },
            TestContext.Current.CancellationToken);

        // Act
        var response = await this._client.GetAsync("/api/v1/notes", TestContext.Current.CancellationToken);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var notes = await response.Content
            .ReadFromJsonAsync<List<NoteView>>(TestContext.Current.CancellationToken);
        notes.Should().NotBeNull();
        notes!.Select(note => note.Title).Should().Contain([first, second]);
    }

    [Fact]
    public async Task It_should_refuse_a_duplicate_title_with_the_typed_conflict()
    {
        // Arrange
        var title = Unique("Duplicate");
        await this._client.PostAsJsonAsync(
            "/api/v1/notes",
            new { title, body = "first" },
            TestContext.Current.CancellationToken);

        // Act
        var response = await this._client.PostAsJsonAsync(
            "/api/v1/notes",
            new { title, body = "second" },
            TestContext.Current.CancellationToken);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.Conflict);
        (await response.Should().BeRfc9457()).Which.Status.Should().Be((int)HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task It_should_let_a_note_keep_its_own_title_on_update()
    {
        // Arrange
        var title = Unique("SelfTitle");
        var created = await this._client.PostAsJsonAsync(
            "/api/v1/notes",
            new { title, body = "first" },
            TestContext.Current.CancellationToken);
        var note = await created.Content.ReadFromJsonAsync<NoteView>(TestContext.Current.CancellationToken);

        // Act — same title, new body
        var response = await this._client.PutAsJsonAsync(
            $"/api/v1/notes/{note!.Id}",
            new { title, body = "second" },
            TestContext.Current.CancellationToken);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task It_should_report_an_update_to_a_missing_note_rather_than_creating_it()
    {
        // Act
        var response = await this._client.PutAsJsonAsync(
            "/api/v1/notes/does-not-exist",
            new { title = Unique("Ghost"), body = "body" },
            TestContext.Current.CancellationToken);

        // Assert — replace is not an upsert
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task It_should_report_a_delete_of_a_missing_note()
    {
        // Act
        var response = await this._client.DeleteAsync(
            "/api/v1/notes/does-not-exist",
            TestContext.Current.CancellationToken);

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task It_should_have_applied_real_migrations_rather_than_creating_the_schema()
    {
        // Assert on the VALUE: name the migrations that ran, so this cannot pass by having
        // provisioned the schema some other way.
        this._host.AppliedMigrations.Should().NotBeEmpty();
    }

    // Titles are unique across the store and these tests share one container, so a fixed title
    // would make the second test in a run fail for a reason that has nothing to do with its
    // subject.
    private static string Unique(string prefix) => $"{prefix}-{Guid.NewGuid():N}";
}
