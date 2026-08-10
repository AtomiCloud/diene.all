using FluentAssertions;
using FluentAssertions.Execution;
using FluentAssertions.Primitives;

namespace AtomiCloud.Diene.Results.TestHelper;

/// <summary>FluentAssertions entry points for Result and Option values.</summary>
public static class ResultAssertionExtensions
{
    /// <summary>Creates assertions for a Result.</summary>
    public static ResultAssertions<T, E> Should<T, E>(this Result<T, E> subject) => new(subject);

    /// <summary>Creates assertions for an Option.</summary>
    public static OptionAssertions<T> Should<T>(this Option<T> subject) => new(subject);

    /// <summary>Creates assertions for an asynchronous Result.</summary>
    public static TaskResultAssertions<T, E> Should<T, E>(this Task<Result<T, E>> subject) => new(subject);
}

/// <summary>Assertions for Result values.</summary>
public sealed class ResultAssertions<T, E>(Result<T, E> subject)
{
    /// <summary>Gets the assertion subject.</summary>
    public Result<T, E> Subject { get; } = subject;

    /// <summary>Asserts that the Result is successful and returns its value.</summary>
    public AndWhichConstraint<ResultAssertions<T, E>, T> BeOk(string because = "", params object[] becauseArgs)
    {
        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(Subject.IsSuccess())
            .FailWith("Expected result to be successful{reason}, but found {0}.", Subject);
        return new(this, Subject.Get());
    }

    /// <summary>Asserts that the Result is successful with the expected value.</summary>
    public AndConstraint<ResultAssertions<T, E>> BeOk(T expected, string because = "", params object[] becauseArgs)
    {
        BeOk(because, becauseArgs).Which.Should().BeEquivalentTo(expected, because, becauseArgs);
        return new(this);
    }

    /// <summary>Asserts that the Result is a failure and returns its error.</summary>
    public AndWhichConstraint<ResultAssertions<T, E>, E> BeErr(string because = "", params object[] becauseArgs)
    {
        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(Subject.IsFailure())
            .FailWith("Expected result to be a failure{reason}, but found {0}.", Subject);
        return new(this, Subject.GetFailure());
    }

    /// <summary>Asserts that the Result is a failure with the expected error.</summary>
    public AndConstraint<ResultAssertions<T, E>> BeErr(E expected, string because = "", params object[] becauseArgs)
    {
        BeErr(because, becauseArgs).Which.Should().BeEquivalentTo(expected, because, becauseArgs);
        return new(this);
    }
}

/// <summary>Assertions for Option values.</summary>
public sealed class OptionAssertions<T>(Option<T> subject)
{
    /// <summary>Gets the assertion subject.</summary>
    public Option<T> Subject { get; } = subject;

    /// <summary>Asserts that the Option contains a value and returns it.</summary>
    public AndWhichConstraint<OptionAssertions<T>, T> BeSome(string because = "", params object[] becauseArgs)
    {
        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(Subject.IsSome())
            .FailWith("Expected option to contain a value{reason}, but found None.");
        return new(this, Subject.Get());
    }

    /// <summary>Asserts that the Option contains the expected value.</summary>
    public AndConstraint<OptionAssertions<T>> BeSome(T expected, string because = "", params object[] becauseArgs)
    {
        BeSome(because, becauseArgs).Which.Should().BeEquivalentTo(expected, because, becauseArgs);
        return new(this);
    }

    /// <summary>Asserts that the Option is empty.</summary>
    public AndConstraint<OptionAssertions<T>> BeNone(string because = "", params object[] becauseArgs)
    {
        Execute.Assertion
            .BecauseOf(because, becauseArgs)
            .ForCondition(Subject.IsNone())
            .FailWith("Expected option to be None{reason}, but found {0}.", Subject);
        return new(this);
    }
}

/// <summary>Assertions for Task-wrapped Result values.</summary>
public sealed class TaskResultAssertions<T, E>(Task<Result<T, E>> subject)
{
    /// <summary>Asserts that the asynchronous Result succeeds.</summary>
    public async Task<AndWhichConstraint<ResultAssertions<T, E>, T>> BeOkAsync(
        string because = "",
        params object[] becauseArgs) =>
        (await subject.ConfigureAwait(false)).Should().BeOk(because, becauseArgs);

    /// <summary>Asserts that the asynchronous Result fails.</summary>
    public async Task<AndWhichConstraint<ResultAssertions<T, E>, E>> BeErrAsync(
        string because = "",
        params object[] becauseArgs) =>
        (await subject.ConfigureAwait(false)).Should().BeErr(because, becauseArgs);
}
