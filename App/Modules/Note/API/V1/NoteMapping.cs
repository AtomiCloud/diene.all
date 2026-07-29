using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Problems.Catalog;
using AtomiCloud.DotnetBase.App.Error;
using AtomiCloud.DotnetBase.Lib.Note;
using FluentValidation.Results;

namespace AtomiCloud.DotnetBase.App.Modules.Note.API.V1;

/// <summary>Translation between the note domain and this API version's wire shapes.</summary>
internal static class NoteMapping
{
    /// <summary>Projects a domain note onto its wire view.</summary>
    /// <param name="principal">The domain value.</param>
    /// <returns>The wire view.</returns>
    public static NoteView ToView(this NotePrincipal principal) =>
        new(principal.Id, principal.Record.Title, principal.Record.Body);

    /// <summary>Projects a validated request onto the domain record.</summary>
    /// <param name="request">The validated request. Both members are non-null by then.</param>
    /// <returns>The domain record.</returns>
    public static NoteRecord ToRecord(this NoteUpsertRequest request) =>
        new() { Title = request.Title!, Body = request.Body! };

    /// <summary>
    /// Turns a FluentValidation result into the portable <c>validation_error</c> problem, so a
    /// rejected body leaves through the SAME RFC 9457 path as every other failure.
    /// </summary>
    /// <param name="result">The failed validation result.</param>
    /// <returns>The typed problem.</returns>
    public static IDomainProblem ToProblem(this ValidationResult result) =>
        new ValidationError(
            "The request body is not valid.",
            result.Errors
                .GroupBy(failure => failure.PropertyName, StringComparer.Ordinal)
                .ToDictionary(
                    group => group.Key,
                    group => group.Select(failure => failure.ErrorMessage).ToArray(),
                    StringComparer.Ordinal));

    /// <summary>
    /// Restates the domain's portable conflict as this service's documented, typed conflict.
    /// </summary>
    /// <remarks>
    /// <see cref="NoteTitleConflict"/> is registered against <c>POST /api/v1/notes</c> and
    /// <c>PUT /api/v1/notes/{id}</c>. A problem type whose metadata names HTTP endpoints is an
    /// API-layer concept, so the domain layer cannot reference it and correctly emits the
    /// portable <see cref="EntityConflict"/> instead. This is the ONE place that bridges the two,
    /// so a second conflict kind has exactly one place to be added.
    /// </remarks>
    /// <param name="problem">The problem the domain produced.</param>
    /// <param name="title">The title that was requested.</param>
    /// <returns>The typed conflict, or the original problem untouched.</returns>
    public static IDomainProblem AsTitleConflict(IDomainProblem problem, string title) =>
        problem is EntityConflict ? new NoteTitleConflict(title) : problem;
}
