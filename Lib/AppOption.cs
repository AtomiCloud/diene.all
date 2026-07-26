using System.ComponentModel.DataAnnotations;
using Microsoft.Extensions.DependencyInjection;

namespace AtomiCloud.Diene.Config;

/// <summary>
/// The mandatory service-tree block every Diene service carries.
/// </summary>
/// <remarks>
/// It lives in the config lib rather than standard-config on purpose: it is the contract every
/// other lib reads — otel maps it onto resource attributes, composition roots map it onto the
/// problems lib's identity — so keeping it in the lowest common layer avoids an
/// otel → standard-config edge.
/// </remarks>
public sealed class AppOption
{
    /// <summary>The config key this block binds to.</summary>
    public const string Key = "App";

    /// <summary>The landscape the service is deployed into. Identity, never a secret.</summary>
    [Required]
    [MinLength(2)]
    public string Landscape { get; set; } = "";

    /// <summary>The platform the service belongs to.</summary>
    [Required]
    [MinLength(2)]
    public string Platform { get; set; } = "";

    /// <summary>The service name.</summary>
    [Required]
    [MinLength(2)]
    public string Service { get; set; } = "";

    /// <summary>The module within the service.</summary>
    [Required]
    [MinLength(2)]
    public string Module { get; set; } = "";

    /// <summary>The service version, as three dot-separated numbers.</summary>
    [Required]
    [RegularExpression(@"\d+\.\d+\.\d+")]
    public string Version { get; set; } = "";
}

/// <summary>Registers the service-tree block.</summary>
public static class AppOptionExtensions
{
    /// <summary>
    /// Registers <see cref="AppOption" /> at <see cref="AppOption.Key" />, so a service missing
    /// its service-tree identity fails at startup rather than at first use.
    /// </summary>
    public static IServiceCollection AddAtomiServiceTree(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);
        return services.RegisterOption<AppOption>(AppOption.Key).Services;
    }
}
