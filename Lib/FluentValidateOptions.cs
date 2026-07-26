using FluentValidation;
using Microsoft.Extensions.Options;

namespace AtomiCloud.Diene.Config;

/// <summary>
/// Runs a FluentValidation validator as an options validation, so a rule failure surfaces
/// through the same <c>ValidateOnStart</c> fail-fast path as a DataAnnotations failure.
/// </summary>
/// <remarks>
/// Validation deliberately runs at BIND time, which is after every layer has been merged —
/// a sparse landscape overlay or a single env override is never validated on its own.
/// </remarks>
internal sealed class FluentValidateOptions<T>(IValidator<T> validator, string key) : IValidateOptions<T>
    where T : class
{
    public ValidateOptionsResult Validate(string? name, T options)
    {
        var result = validator.Validate(options);
        if (result.IsValid) return ValidateOptionsResult.Success;

        var failures = result.Errors.Select(failure =>
            $"Config '{key}:{failure.PropertyName}' is invalid: {failure.ErrorMessage}");

        return ValidateOptionsResult.Fail(failures);
    }
}
