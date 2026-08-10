using System.ComponentModel;
using System.Text.Json.Serialization;
using AtomiCloud.Diene.Problems;
using AtomiCloud.Diene.Results;

namespace AtomiCloud.Diene.AuthEngine;

/// <summary>The identity bound to one deferred app-handoff nonce.</summary>
/// <param name="Subject">The validated OIDC <c>sub</c> captured at mint time.</param>
/// <param name="Email">The validated OIDC email captured at mint time.</param>
public sealed record DeferredPayload(string Subject, string Email);

/// <summary>The opaque nonce returned to the authenticated web session.</summary>
/// <param name="Nonce">A 32-byte RFC 4648 base64url value without padding.</param>
/// <param name="ExpiresAt">The fixed fifteen-minute expiry instant.</param>
// Serialized by ASP.NET for downstream callers; production does not read its own response DTO.
// ReSharper disable NotAccessedPositionalProperty.Global
public sealed record DeferredHandoff(string Nonce, DateTimeOffset ExpiresAt);
// ReSharper restore NotAccessedPositionalProperty.Global

/// <summary>The Logto one-time token returned after a successful redeem.</summary>
/// <param name="Token">The one-time login token.</param>
/// <param name="Email">The user's current primary email.</param>
/// <param name="ExpiresIn">The fixed provider-token lifetime in seconds.</param>
// Serialized by ASP.NET for downstream callers; production does not read its own response DTO.
// ReSharper disable NotAccessedPositionalProperty.Global
public sealed record DeferredExchange(string Token, string Email, int ExpiresIn);
// ReSharper restore NotAccessedPositionalProperty.Global

/// <summary>The empty JSON document accepted by the authenticated mint endpoint.</summary>
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
// Constructed by System.Text.Json rather than an explicit new expression.
// ReSharper disable once ClassNeverInstantiated.Global
public sealed class DeferredMintRequest;

/// <summary>Telemetry supplied by the mobile app during redemption.</summary>
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
// Constructed by System.Text.Json rather than an explicit new expression.
// ReSharper disable once ClassNeverInstantiated.Global
public sealed class DeferredDevice
{
    /// <summary>Gets the mobile platform, either <c>android</c> or <c>ios</c>.</summary>
    [JsonPropertyName("platform")]
    [JsonRequired]
    public string Platform { get; init; } = string.Empty;

    /// <summary>Gets the app version when the client supplies one.</summary>
    [JsonPropertyName("appVersion")]
    // Accepted as forwardable telemetry even though v1 validates only the platform.
    // ReSharper disable once UnusedMember.Global
    public string? AppVersion { get; init; }

    /// <summary>Gets the operating-system version when the client supplies one.</summary>
    [JsonPropertyName("osVersion")]
    // Accepted as forwardable telemetry even though v1 validates only the platform.
    // ReSharper disable once UnusedMember.Global
    public string? OsVersion { get; init; }

    /// <summary>Gets the device model when the client supplies one.</summary>
    [JsonPropertyName("model")]
    // Accepted as forwardable telemetry even though v1 validates only the platform.
    // ReSharper disable once UnusedMember.Global
    public string? Model { get; init; }
}

/// <summary>The strict v1 JSON document accepted by the unauthenticated redeem endpoint.</summary>
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
// Constructed by System.Text.Json rather than an explicit new expression.
// ReSharper disable once ClassNeverInstantiated.Global
public sealed class DeferredRedeemRequest
{
    /// <summary>Gets the opaque 43-character app-handoff nonce.</summary>
    [JsonPropertyName("nonce")]
    [JsonRequired]
    public string Nonce { get; init; } = string.Empty;

    /// <summary>Gets telemetry about the redeeming device.</summary>
    [JsonPropertyName("device")]
    [JsonRequired]
    public DeferredDevice Device { get; init; } = null!;
}

/// <summary>
/// The single no-oracle failure returned for every malformed, expired, replayed,
/// rebound, suspended, deleted, or upstream-failed app-handoff redemption.
/// </summary>
[Description("The app handoff is expired or invalid.")]
public sealed class AppHandoffExpired : IDomainProblem
{
    /// <inheritdoc />
    [JsonIgnore]
    public string Id => "app_handoff_expired";

    /// <inheritdoc />
    [JsonIgnore]
    public string Title => "App handoff expired";

    /// <inheritdoc />
    [JsonIgnore]
    public string Detail => "This app handoff is expired or invalid.";

    /// <inheritdoc />
    [JsonIgnore]
    public string Version => "v1";
}

/// <summary>The state persisted for a deferred nonce.</summary>
public enum DeferredTokenState
{
    /// <summary>The nonce is available for one claimant.</summary>
    // Store implementations live in consuming services as well as TestHelper.
    // ReSharper disable once UnusedMember.Global
    Active,

    /// <summary>One claimant owns the nonce and it can never become active again.</summary>
    // Store implementations live in consuming services as well as TestHelper.
    // ReSharper disable once UnusedMember.Global
    Claimed,

    /// <summary>The provider token was minted and the response may be returned.</summary>
    Consumed,

    /// <summary>The claim failed closed and may never be retried.</summary>
    Revoked,
}

/// <summary>
/// Persistent storage for deferred app-handoff nonces. Implementations must store only
/// the digest supplied as <paramref name="tokenDigest" />, enforce the TTL, and make
/// <see cref="Consume" /> a single atomic <see cref="DeferredTokenState.Active" /> to
/// <see cref="DeferredTokenState.Claimed" /> transition.
/// </summary>
public interface IDeferredTokenStore
{
    /// <summary>Stores a new active nonce record for the fixed retention window.</summary>
    Task<Result<Unit, IDomainProblem>> Put(
        string tokenDigest,
        DeferredPayload payload,
        TimeSpan ttl,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Atomically claims one active, unexpired nonce. Missing, expired, or non-active
    /// records return <see cref="Option{T}" /> none and never reveal which case occurred.
    /// </summary>
    Task<Result<Option<DeferredPayload>, IDomainProblem>> Consume(
        string tokenDigest,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Settles a claimed record as consumed or revoked. A claimed record never returns
    /// to active, including when the caller or process fails before settlement.
    /// </summary>
    Task<Result<Unit, IDomainProblem>> Settle(
        string tokenDigest,
        DeferredTokenState state,
        CancellationToken cancellationToken = default);
}

/// <summary>Mints and exchanges deferred app-handoff nonces.</summary>
public interface IDeferredTokenMinter
{
    /// <summary>Mints a nonce bound to an authenticated subject and email.</summary>
    Task<Result<DeferredHandoff, IDomainProblem>> Mint(
        DeferredPayload payload,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Claims the nonce exactly once, re-resolves the user, and mints a Logto one-time
    /// token only after the identity checks pass.
    /// </summary>
    Task<Result<DeferredExchange, IDomainProblem>> Exchange(
        string token,
        CancellationToken cancellationToken = default);
}

/// <summary>The Logto user fields required by redeem-time identity validation.</summary>
/// <param name="Subject">The resolved Logto user id.</param>
/// <param name="PrimaryEmail">The current primary email, when one exists.</param>
/// <param name="IsSuspended">Whether the provider has suspended the user.</param>
// The subject is part of the public management result even though this adapter already knows it.
// ReSharper disable once NotAccessedPositionalProperty.Global
public sealed record AuthManagementUser(string Subject, string? PrimaryEmail, bool IsSuspended);

/// <summary>
/// IdP management operations used by app handoff and onboarding. Logto is the sole v1
/// adapter, while this seam keeps provider HTTP out of the engine decisions and gives
/// consumers one fakeable boundary.
/// </summary>
public interface IAuthManagement
{
    /// <summary>Reads a user, returning none when the provider reports 404.</summary>
    Task<Result<Option<AuthManagementUser>, IDomainProblem>> GetUser(
        string userId,
        CancellationToken cancellationToken = default);

    /// <summary>Mints a 120-second email-bound Logto one-time sign-in token.</summary>
    Task<Result<string, IDomainProblem>> MintOneTimeToken(
        string email,
        CancellationToken cancellationToken = default);

    /// <summary>Writes one custom-data claim.</summary>
    // The full management seam is consumer-facing; app handoff itself needs only the two methods above.
    // ReSharper disable once UnusedMember.Global
    // ReSharper disable once UnusedMemberInSuper.Global
    Task<Result<Unit, IDomainProblem>> SetClaim(
        string userId,
        string key,
        string value,
        CancellationToken cancellationToken = default);

    /// <summary>Removes one custom-data claim.</summary>
    // ReSharper disable once UnusedMember.Global
    // ReSharper disable once UnusedMemberInSuper.Global
    Task<Result<Unit, IDomainProblem>> RemoveClaim(
        string userId,
        string key,
        CancellationToken cancellationToken = default);

    /// <summary>Assigns one provider role to a user.</summary>
    // ReSharper disable once UnusedMember.Global
    // ReSharper disable once UnusedMemberInSuper.Global
    Task<Result<Unit, IDomainProblem>> AssignRole(
        string userId,
        string roleId,
        CancellationToken cancellationToken = default);

    /// <summary>Removes one provider role from a user.</summary>
    // ReSharper disable once UnusedMember.Global
    // ReSharper disable once UnusedMemberInSuper.Global
    Task<Result<Unit, IDomainProblem>> RemoveRole(
        string userId,
        string roleId,
        CancellationToken cancellationToken = default);

    /// <summary>Deletes one provider user.</summary>
    // ReSharper disable once UnusedMember.Global
    // ReSharper disable once UnusedMemberInSuper.Global
    Task<Result<Unit, IDomainProblem>> DeleteUser(
        string userId,
        CancellationToken cancellationToken = default);
}
