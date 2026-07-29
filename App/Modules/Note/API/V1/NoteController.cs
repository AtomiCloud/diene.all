using Asp.Versioning;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;
using AtomiCloud.Diene.ServerEngine.Mvc;
using AtomiCloud.DotnetBase.Lib.Note;
using FluentValidation;
using Microsoft.AspNetCore.Mvc;

namespace AtomiCloud.DotnetBase.App.Modules.Note.API.V1;

/// <summary>
/// The note CRUD endpoints — the FENCED sample. A downstream consumer deletes
/// <c>App/Modules/Note/</c> and keeps every piece of machinery around it.
/// </summary>
/// <remarks>
/// Three rules hold every action here, and each one exists because breaking it puts a SECOND
/// error contract on the wire:
/// <list type="number">
/// <item>No <c>[ApiController]</c>. It installs an automatic 400 in ASP.NET's own shape, so a
/// malformed body would be rendered by the framework instead of as RFC 9457. Without it the body
/// arrives as a null model, which is why every write action validates one.</item>
/// <item>Never <c>BadRequest(...)</c>, <c>NotFound(...)</c> or <c>Problem(...)</c>. Exactly one
/// thing writes an error response and it is the shipped filter.</item>
/// <item>Every return goes through <c>ResolveAsync</c> or <c>ResolveEmptyAsync</c>, which raise
/// the typed problem for that filter to render.</item>
/// </list>
/// The version lives in the route as a segment because the host registers
/// <c>UrlSegmentApiVersionReader</c> with a default of 1.0.
/// </remarks>
/// <param name="notes">The note domain service.</param>
/// <param name="validator">The request validator, resolved from the assembly scan.</param>
[ApiVersion("1.0")]
[Route("api/v{version:apiVersion}/notes")]
public sealed class NoteController(INotes notes, IValidator<NoteUpsertRequest> validator) : AtomiController
{
    /// <summary>Lists every note.</summary>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Every note. An empty store is an empty list, not a 404.</returns>
    [HttpGet]
    public Task<ActionResult<IReadOnlyList<NoteView>>> List(CancellationToken cancellationToken) =>
        this.ResolveAsync(notes
            .List(cancellationToken)
            .Map(found => (IReadOnlyList<NoteView>)[.. found.Select(NoteMapping.ToView)]));

    /// <summary>Reads one note.</summary>
    /// <param name="id">The note identity.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The note, or the domain's <c>entity_not_found</c> rendered as RFC 9457.</returns>
    [HttpGet("{id}")]
    public Task<ActionResult<NoteView>> Get(string id, CancellationToken cancellationToken) =>
        this.ResolveAsync(notes.Get(id, cancellationToken).Map(NoteMapping.ToView));

    /// <summary>Creates a note.</summary>
    /// <param name="request">The request body. Null when the body is absent or unparseable.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The created note, or a validation or conflict problem.</returns>
    [HttpPost]
    public async Task<ActionResult<NoteView>> Create(
        [FromBody] NoteUpsertRequest? request,
        CancellationToken cancellationToken)
    {
        var accepted = await this.Accept(request, cancellationToken).ConfigureAwait(false);
        if (accepted.IsFailure(out var rejection)) return this.Resolve(Fail(rejection));

        var record = accepted.Get().ToRecord();
        return await this
            .ResolveAsync(notes
                .Create(record, cancellationToken)
                .MapFailure(problem => NoteMapping.AsTitleConflict(problem, record.Title))
                .Map(NoteMapping.ToView))
            .ConfigureAwait(false);
    }

    /// <summary>Replaces a note's content. Never creates one.</summary>
    /// <param name="id">The note identity.</param>
    /// <param name="request">The request body. Null when the body is absent or unparseable.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The updated note, or a validation, not-found, or conflict problem.</returns>
    [HttpPut("{id}")]
    public async Task<ActionResult<NoteView>> Update(
        string id,
        [FromBody] NoteUpsertRequest? request,
        CancellationToken cancellationToken)
    {
        var accepted = await this.Accept(request, cancellationToken).ConfigureAwait(false);
        if (accepted.IsFailure(out var rejection)) return this.Resolve(Fail(rejection));

        var record = accepted.Get().ToRecord();
        return await this
            .ResolveAsync(notes
                .Update(id, record, cancellationToken)
                .MapFailure(problem => NoteMapping.AsTitleConflict(problem, record.Title))
                .Map(NoteMapping.ToView))
            .ConfigureAwait(false);
    }

    /// <summary>Deletes a note.</summary>
    /// <param name="id">The note identity.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>204 on success, or the domain's <c>entity_not_found</c>.</returns>
    [HttpDelete("{id}")]
    public Task<ActionResult> Delete(string id, CancellationToken cancellationToken) =>
        this.ResolveEmptyAsync(notes.Delete(id, cancellationToken));

    private static Result<NoteView, IDomainProblem> Fail(IDomainProblem problem) =>
        Result.Err<NoteView, IDomainProblem>(problem);

    /// <summary>
    /// Turns an unvalidated body into a validated one, as a Result. The null check is not
    /// defensive noise: without <c>[ApiController]</c> an absent or unparseable body reaches the
    /// action as null, and reporting that as a validation problem is what keeps it on the RFC
    /// 9457 path instead of becoming a 500.
    /// </summary>
    private async Task<Result<NoteUpsertRequest, IDomainProblem>> Accept(
        NoteUpsertRequest? request,
        CancellationToken cancellationToken)
    {
        if (request is null)
        {
            var absent = new FluentValidation.Results.ValidationResult(
                [new FluentValidation.Results.ValidationFailure("body", "a JSON object body is required")]);
            return Result.Err<NoteUpsertRequest, IDomainProblem>(absent.ToProblem());
        }

        var validation = await validator.ValidateAsync(request, cancellationToken).ConfigureAwait(false);

        return validation.IsValid
            ? Result.Ok<NoteUpsertRequest, IDomainProblem>(request)
            : Result.Err<NoteUpsertRequest, IDomainProblem>(validation.ToProblem());
    }
}
