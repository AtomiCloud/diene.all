using AtomiCloud.Diene.AuthEngine.Tokens;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Problems.Catalog;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.AuthEngine.TestHelper.Assertions;

/// <summary>
/// Assertions over auth outcomes, so a consumer does not re-derive the same unwrapping
/// and problem-shape checks in every test.
/// </summary>
/// <remarks>
/// Each assertion throws <see cref="AuthAssertionException" /> with the actual value in
/// the message. An assertion that reports only "expected authorized" without saying what
/// it found makes the failing test a starting point for an investigation rather than an
/// answer.
/// </remarks>
public static class AuthResultAssertions
{
    /// <summary>Asserts the outcome succeeded and returns the claims for further assertions.</summary>
    public static AuthClaims ShouldBeAuthorized(this Result<AuthClaims, IDomainProblem> subject)
    {
        if (subject.IsFailure(out var problem))
        {
            throw new AuthAssertionException(
                $"Expected an authorized outcome but found the problem '{problem.Id}': {problem.Detail}");
        }

        return subject.Get();
    }

    /// <summary>Asserts the outcome failed, and returns the problem.</summary>
    public static IDomainProblem ShouldBeRefused(this Result<AuthClaims, IDomainProblem> subject)
    {
        if (subject.IsSuccess(out var claims))
        {
            throw new AuthAssertionException(
                $"Expected a refusal but the outcome authorized subject '{claims.Subject}'.");
        }

        return subject.GetFailure();
    }

    /// <summary>Asserts the outcome failed as unauthenticated — the caller has no established identity.</summary>
    public static Unauthenticated ShouldBeUnauthenticated(this Result<AuthClaims, IDomainProblem> subject)
    {
        var problem = subject.ShouldBeRefused();
        if (problem is not Unauthenticated unauthenticated)
        {
            throw new AuthAssertionException(
                $"Expected an Unauthenticated problem but found '{problem.GetType().Name}' ({problem.Id}).");
        }

        return unauthenticated;
    }

    /// <summary>Asserts the outcome failed as unauthorized — an established identity lacking a permission.</summary>
    public static Unauthorized ShouldBeUnauthorized(this Result<AuthClaims, IDomainProblem> subject)
    {
        var problem = subject.ShouldBeRefused();
        if (problem is not Unauthorized unauthorized)
        {
            throw new AuthAssertionException(
                $"Expected an Unauthorized problem but found '{problem.GetType().Name}' ({problem.Id}).");
        }

        return unauthorized;
    }

    /// <summary>Asserts the refusal names exactly the supplied required scopes.</summary>
    public static Unauthorized ShouldRequireScopes(
        this Result<AuthClaims, IDomainProblem> subject,
        params string[] expected)
    {
        ArgumentNullException.ThrowIfNull(expected);

        var unauthorized = subject.ShouldBeUnauthorized();
        var actual = unauthorized.Required.OrderBy(scope => scope, StringComparer.Ordinal).ToArray();
        var wanted = expected.OrderBy(scope => scope, StringComparer.Ordinal).ToArray();

        if (!actual.SequenceEqual(wanted, StringComparer.Ordinal))
        {
            throw new AuthAssertionException(
                $"Expected required scopes [{string.Join(", ", wanted)}] but found [{string.Join(", ", actual)}].");
        }

        return unauthorized;
    }

    /// <summary>Asserts the claims carry exactly the supplied granted scopes.</summary>
    public static AuthClaims ShouldGrantScopes(this AuthClaims subject, params string[] expected)
    {
        ArgumentNullException.ThrowIfNull(subject);
        ArgumentNullException.ThrowIfNull(expected);

        var actual = subject.Scopes.OrderBy(scope => scope, StringComparer.Ordinal).ToArray();
        var wanted = expected.OrderBy(scope => scope, StringComparer.Ordinal).ToArray();

        if (!actual.SequenceEqual(wanted, StringComparer.Ordinal))
        {
            throw new AuthAssertionException(
                $"Expected granted scopes [{string.Join(", ", wanted)}] but found [{string.Join(", ", actual)}].");
        }

        return subject;
    }

    /// <summary>Asserts the claims belong to the supplied subject.</summary>
    public static AuthClaims ShouldHaveSubject(this AuthClaims subject, string expected)
    {
        ArgumentNullException.ThrowIfNull(subject);

        if (!string.Equals(subject.Subject, expected, StringComparison.Ordinal))
        {
            throw new AuthAssertionException(
                $"Expected subject '{expected}' but found '{subject.Subject}'.");
        }

        return subject;
    }
}
