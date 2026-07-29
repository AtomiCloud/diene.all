using AtomiCloud.Diene.Problems.Catalog;
using AtomiCloud.Diene.Problems.TestHelper;
using AtomiCloud.Diene.Results.TestHelper;
using AtomiCloud.DotnetBase.Lib.Note;
using AtomiCloud.DotnetBase.UnitTest.Note.Doubles;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Note;

public class Notes_Delete
{
    [Fact]
    public async Task It_should_delete_an_existing_note()
    {
        // Arrange
        var store = new FakeNoteStore();
        store.Seed("note-1", new NoteRecord { Title = "Doomed", Body = "body" });
        var subject = new Notes(store, store);

        // Act
        var actual = await subject.Delete("note-1", TestContext.Current.CancellationToken);

        // Assert
        ResultAssertionExtensions.Should(actual).BeOk();
        var remaining = await store.All(TestContext.Current.CancellationToken);
        remaining.Should().BeEmpty();
    }

    [Fact]
    public async Task It_should_report_a_deletion_that_had_nothing_to_delete()
    {
        // Arrange — a delete that removed nothing is not a success dressed up as one
        var store = new FakeNoteStore();
        var subject = new Notes(store, store);

        // Act
        var actual = await subject.Delete("absent", TestContext.Current.CancellationToken);

        // Assert
        actual.Should().BeErrProblem<EntityNotFound>()
            .Which.RequestIdentifier.Should().Be("absent");
    }

    [Fact]
    public async Task It_should_report_the_second_delete_of_the_same_note_as_not_found()
    {
        // Arrange
        var store = new FakeNoteStore();
        store.Seed("note-1", new NoteRecord { Title = "Doomed", Body = "body" });
        var subject = new Notes(store, store);

        // Act
        var first = await subject.Delete("note-1", TestContext.Current.CancellationToken);
        var second = await subject.Delete("note-1", TestContext.Current.CancellationToken);

        // Assert
        ResultAssertionExtensions.Should(first).BeOk();
        second.Should().BeErrProblem<EntityNotFound>();
    }
}
