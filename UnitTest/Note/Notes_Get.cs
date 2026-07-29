using AtomiCloud.Diene.Problems.Catalog;
using AtomiCloud.Diene.Problems.TestHelper;
using AtomiCloud.Diene.Results.TestHelper;
using AtomiCloud.DotnetBase.Lib.Note;
using AtomiCloud.DotnetBase.UnitTest.Note.Doubles;
using FluentAssertions;

namespace AtomiCloud.DotnetBase.UnitTest.Note;

// BeOk is reached through the explicit static call on purpose. Both published TestHelpers put a
// Should() extension on Result<T, IDomainProblem>, and the Problems one wins overload resolution
// because its E is fixed — so the instance-style actual.Should() only ever offers BeErrProblem.
// The alternative, actual.Ok().Should().BeSome(), compiles but throws away the error text on
// failure, which is the one thing a failing assertion here needs to print.
public class Notes_Get
{
    [Fact]
    public async Task It_should_return_the_note_when_it_exists()
    {
        // Arrange
        var store = new FakeNoteStore();
        var seeded = store.Seed("note-1", new NoteRecord { Title = "Title", Body = "Body" });
        var subject = new Notes(store, store);

        // Act
        var actual = await subject.Get("note-1", TestContext.Current.CancellationToken);

        // Assert
        ResultAssertionExtensions.Should(actual).BeOk().Which.Should().Be(seeded);
    }

    [Fact]
    public async Task It_should_report_a_missing_note_as_a_value_rather_than_null_or_a_throw()
    {
        // Arrange
        var store = new FakeNoteStore();
        var subject = new Notes(store, store);

        // Act
        var actual = await subject.Get("absent", TestContext.Current.CancellationToken);

        // Assert
        actual.Should().BeErrProblem<EntityNotFound>()
            .Which.RequestIdentifier.Should().Be("absent");
    }

    [Fact]
    public async Task It_should_name_the_note_type_on_the_not_found_problem()
    {
        // Arrange
        var store = new FakeNoteStore();
        var subject = new Notes(store, store);

        // Act
        var actual = await subject.Get("absent", TestContext.Current.CancellationToken);

        // Assert
        var problem = actual.Should().BeErrProblem<EntityNotFound>().Which;
        problem.TypeName.Should().Be(typeof(NotePrincipal).FullName);
        problem.Detail.Should().Be("No note carries the id 'absent'.");
    }
}
