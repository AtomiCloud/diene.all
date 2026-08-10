using System.ComponentModel.DataAnnotations;

namespace AtomiCloud.Diene.Problems;

/// <summary>The engine-owned ErrorPortal configuration block schema.</summary>
public sealed class ErrorPortalOption
{
    /// <summary>The conventional configuration section key.</summary>
    public const string Key = "ErrorPortal";

    /// <summary>Gets or sets whether the error portal is enabled.</summary>
    public bool Enabled { get; set; } = true;

    /// <summary>Gets or sets the URI scheme.</summary>
    [Required]
    [AllowedValues("http", "https")]
    public string Scheme { get; set; } = "https";

    /// <summary>Gets or sets the canonical host or host:port.</summary>
    [Required]
    public string Host { get; set; } = string.Empty;
}
