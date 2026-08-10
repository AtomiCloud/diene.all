using FluentValidation;

namespace AtomiCloud.Diene.StandardConfig.Presets;

/// <summary>
/// A single named S3-compatible object-storage endpoint — Tigris in production, MinIO
/// locally.
/// </summary>
/// <remarks>
/// <para>
/// Provider-agnostic connection block: the landscape matrix picks the provider, the shape
/// stays the same. <see cref="ForcePathStyle" /> is <c>true</c> for MinIO and other
/// path-style endpoints and <c>false</c> for virtual-hosted-style providers such as Tigris.
/// </para>
/// <para>
/// <see cref="AccessKeyId" /> and <see cref="SecretAccessKey" /> are secrets — blank in YAML,
/// injected per landscape (R14/M33).
/// </para>
/// <para>
/// C0-FROZEN (c0-contracts.md §3): matched key-for-key across bun / dotnet / go.
/// </para>
/// </remarks>
public sealed class StorageOption
{
    /// <summary>The config key the whole block binds to.</summary>
    public const string Key = "Storage";

    /// <summary>S3-compatible endpoint URL (for example <c>https://fly.storage.tigris.dev</c>).</summary>
    public string Endpoint { get; set; } = "";

    /// <summary>Region label the endpoint expects.</summary>
    public string Region { get; set; } = "";

    /// <summary>Bucket name.</summary>
    public string Bucket { get; set; } = "";

    /// <summary>Secret — blank-in-yaml, injected per landscape (R14/M33).</summary>
    public string AccessKeyId { get; set; } = "";

    /// <summary>Secret — blank-in-yaml, injected per landscape (R14/M33).</summary>
    public string SecretAccessKey { get; set; } = "";

    /// <summary>Path-style addressing (<c>true</c> for MinIO, <c>false</c> for virtual-hosted).</summary>
    public bool ForcePathStyle { get; set; }
}

/// <summary>Validates one named storage connection.</summary>
public sealed class StorageOptionValidator : AbstractValidator<StorageOption>
{
    /// <summary>Builds the rules.</summary>
    public StorageOptionValidator()
    {
        RuleFor(x => x.Endpoint).NotEmpty();
        RuleFor(x => x.Region).NotEmpty();
        RuleFor(x => x.Bucket).NotEmpty();
    }
}

/// <summary>Validates the whole <c>storage</c> block: UPPERCASE keys, valid entries.</summary>
public sealed class StorageBlockValidator : KeyedBlockValidator<StorageBlock, StorageOption>
{
    /// <summary>Builds the rules.</summary>
    public StorageBlockValidator() : base(new StorageOptionValidator()) { }
}
