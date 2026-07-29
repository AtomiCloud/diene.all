using AtomiCloud.Diene.Problems.Catalog;
using AtomiCloud.Diene.Problems.TestHelper;
using AtomiCloud.Diene.Results.TestHelper;
using AtomiCloud.DotnetBase.Lib.Note;
using AtomiCloud.DotnetBase.UnitTest.Note.Doubles;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Note;

public class Notes_Create
{
    [Fact]
    public async Task It_should_store_the_note_and_return_it_with_its_minted_identity()
    {
        // Arrange
        var store = new FakeNoteStore();
        var subject = new Notes(store, store);
        var input = new NoteRecord { Title = "Fresh", Body = "content" };

        // Act
        var actual = await subject.Create(input, TestContext.Current.CancellationToken);

        // Assert
        var value = ResultAssertionExtensions.Should(actual).BeOk().Which;
        value.Id.Should().Be(store.Minted.Single());
        value.Record.Should().Be(input);
    }

    [Fact]
    public async Task It_should_refuse_a_title_another_note_already_holds()
    {
        // Arrange
        var store = new FakeNoteStore();
        store.Seed("note-1", new NoteRecord { Title = "Taken", Body = "first" });
        var subject = new Notes(store, store);

        // Act
        var actual = await subject.Create(
            new NoteRecord { Title = "Taken", Body = "second" },
            TestContext.Current.CancellationToken);

        // Assert
        actual.Should().BeErrProblem<EntityConflict>()
            .Which.Detail.Should().Be("A note titled 'Taken' already exists.");
    }

    [Fact]
    public async Task It_should_not_write_anything_when_the_title_is_already_held()
    {
        // Arrange
        var store = new FakeNoteStore();
        store.Seed("note-1", new NoteRecord { Title = "Taken", Body = "first" });
        var subject = new Notes(store, store);

        // Act
        await subject.Create(
            new NoteRecord { Title = "Taken", Body = "second" },
            TestContext.Current.CancellationToken);

        // Assert
        store.Minted.Should().BeEmpty();
        var remaining = await store.All(TestContext.Current.CancellationToken);
        remaining.Should().ContainSingle().Which.Record.Body.Should().Be("first");
    }

    [Fact]
    public async Task It_should_name_the_note_type_on_the_conflict_problem()
    {
        // Arrange
        var store = new FakeNoteStore();
        store.Seed("note-1", new NoteRecord { Title = "Taken", Body = "first" });
        var subject = new Notes(store, store);

        // Act
        var actual = await subject.Create(
            new NoteRecord { Title = "Taken", Body = "second" },
            TestContext.Current.CancellationToken);

        // Assert
        actual.Should().BeErrProblem<EntityConflict>()
            .Which.TypeName.Should().Be(typeof(NotePrincipal).FullName);
    }

    [Fact]
    public async Task It_should_reject_a_null_record()
    {
        // Arrange
        var store = new FakeNoteStore();
        var subject = new Notes(store, store);

        // Act
        var act = async () => await subject.Create(null!, TestContext.Current.CancellationToken);

        // Assert
        await act.Should().ThrowAsync<ArgumentNullException>()
            .WithParameterName("record");
    }
}
