using AtomiCloud.Diene.Results.TestHelper;
using AtomiCloud.DotnetBase.Lib.Note;
using AtomiCloud.DotnetBase.UnitTest.Note.Doubles;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Note;

public class Notes_List
{
    [Fact]
    public async Task It_should_return_every_note()
    {
        // Arrange
        var store = new FakeNoteStore();
        store.Seed("note-1", new NoteRecord { Title = "Beta", Body = "second" });
        store.Seed("note-2", new NoteRecord { Title = "Alpha", Body = "first" });
        var subject = new Notes(store, store);

        // Act
        var actual = await subject.List(TestContext.Current.CancellationToken);

        // Assert
        actual.Should().BeOk().Which
            .Select(note => note.Record.Title)
            .Should().Equal("Alpha", "Beta");
    }

    [Fact]
    public async Task It_should_treat_an_empty_store_as_an_empty_list_not_a_problem()
    {
        // Arrange
        var store = new FakeNoteStore();
        var subject = new Notes(store, store);

        // Act
        var actual = await subject.List(TestContext.Current.CancellationToken);

        // Assert
        actual.Should().BeOk().Which.Should().BeEmpty();
    }
}
