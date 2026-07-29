using FluentValidation;

namespace AtomiCloud.DotnetBase.App.Modules.Note.API.V1;

/// <summary>
/// The create/replace request body.
/// </summary>
/// <remarks>
/// Both members are NULLABLE on purpose. This service does not use <c>[ApiController]</c> — that
/// attribute installs an automatic 400 in ASP.NET's own shape, which would put a second error
/// contract on the wire beside RFC 9457 — so a malformed or absent body arrives as a null model
/// or null members rather than being rejected for us. Declaring them nullable means a missing
/// field becomes a validation problem naming the field, instead of a NullReferenceException
/// rendered as an anonymous 500.
/// </remarks>
/// <param name="Title">The note title. Unique across the store.</param>
/// <param name="Body">The note body.</param>
public sealed record NoteUpsertRequest(string? Title, string? Body);

/// <summary>Validates <see cref="NoteUpsertRequest"/>.</summary>
/// <remarks>
/// Registered automatically: the host calls <c>AddValidatorsFromAssembly</c> over this assembly,
/// so a validator beside its contract is picked up without a registration line.
/// </remarks>
public sealed class NoteUpsertRequestValidator : AbstractValidator<NoteUpsertRequest>
{
    /// <summary>The maximum title length. Matches the <c>notes.title</c> column.</summary>
    public const int TitleMaxLength = 256;

    /// <summary>Declares the request's rules.</summary>
    public NoteUpsertRequestValidator()
    {
        this.RuleFor(x => x.Title)
            .NotEmpty()
            .WithMessage("title is required")
            .MaximumLength(TitleMaxLength)
            .WithMessage($"title must be at most {TitleMaxLength} characters");

        // NotNull rather than NotEmpty: an empty body is a legitimate note, an absent one is not.
        this.RuleFor(x => x.Body)
            .NotNull()
            .WithMessage("body is required");
    }
}

/// <summary>The note as this API renders it.</summary>
/// <param name="Id">Stable identity.</param>
/// <param name="Title">The note title.</param>
/// <param name="Body">The note body.</param>
public sealed record NoteView(string Id, string Title, string Body);
