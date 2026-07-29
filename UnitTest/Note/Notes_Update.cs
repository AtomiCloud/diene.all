using AtomiCloud.Diene.Problems.Catalog;
using AtomiCloud.Diene.Problems.TestHelper;
using AtomiCloud.Diene.Results.TestHelper;
using AtomiCloud.DotnetBase.Lib.Note;
using AtomiCloud.DotnetBase.UnitTest.Note.Doubles;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Note;

public class Notes_Update
{
    [Fact]
    public async Task It_should_replace_the_content_of_an_existing_note()
    {
        // Arrange
        var store = new FakeNoteStore();
        store.Seed("note-1", new NoteRecord { Title = "Before", Body = "old" });
        var subject = new Notes(store, store);
        var input = new NoteRecord { Title = "After", Body = "new" };

        // Act
        var actual = await subject.Update("note-1", input, TestContext.Current.CancellationToken);

        // Assert
        var value = ResultAssertionExtensions.Should(actual).BeOk().Which;
        value.Id.Should().Be("note-1");
        value.Record.Should().Be(input);
    }

    [Fact]
    public async Task It_should_let_a_note_keep_its_own_title()
    {
        // Arrange — the title is held, but by the very note being updated, which is not a clash
        var store = new FakeNoteStore();
        store.Seed("note-1", new NoteRecord { Title = "Same", Body = "old" });
        var subject = new Notes(store, store);

        // Act
        var actual = await subject.Update(
            "note-1",
            new NoteRecord { Title = "Same", Body = "new" },
            TestContext.Current.CancellationToken);

        // Assert
        ResultAssertionExtensions.Should(actual).BeOk().Which.Record.Body.Should().Be("new");
    }

    [Fact]
    public async Task It_should_refuse_a_title_a_different_note_holds()
    {
        // Arrange
        var store = new FakeNoteStore();
        store.Seed("note-1", new NoteRecord { Title = "Mine", Body = "first" });
        store.Seed("note-2", new NoteRecord { Title = "Theirs", Body = "second" });
        var subject = new Notes(store, store);

        // Act
        var actual = await subject.Update(
            "note-1",
            new NoteRecord { Title = "Theirs", Body = "stolen" },
            TestContext.Current.CancellationToken);

        // Assert
        actual.Should().BeErrProblem<EntityConflict>()
            .Which.Detail.Should().Be("A note titled 'Theirs' already exists.");
    }

    [Fact]
    public async Task It_should_report_a_missing_note_rather_than_creating_one()
    {
        // Arrange — replace is not an upsert
        var store = new FakeNoteStore();
        var subject = new Notes(store, store);

        // Act
        var actual = await subject.Update(
            "absent",
            new NoteRecord { Title = "Ghost", Body = "body" },
            TestContext.Current.CancellationToken);

        // Assert
        actual.Should().BeErrProblem<EntityNotFound>()
            .Which.RequestIdentifier.Should().Be("absent");

        var remaining = await store.All(TestContext.Current.CancellationToken);
        remaining.Should().BeEmpty();
    }

    [Fact]
    public async Task It_should_reject_a_null_record()
    {
        // Arrange
        var store = new FakeNoteStore();
        var subject = new Notes(store, store);

        // Act
        var act = async () => await subject.Update("note-1", null!, TestContext.Current.CancellationToken);

        // Assert
        await act.Should().ThrowAsync<ArgumentNullException>()
            .WithParameterName("record");
    }
}
