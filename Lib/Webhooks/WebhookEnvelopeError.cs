namespace AtomiCloud.Diene.ServerEngine.Webhooks;

/// <summary>An envelope field that failed the contract, named so the sender can be told which.</summary>
/// <param name="Field">The JSON path of the offending field.</param>
/// <param name="Reason">Why the value was rejected.</param>
public sealed record WebhookEnvelopeError(string Field, string Reason)
{
    /// <summary>Renders the failure as a single diagnostic line.</summary>
    public override string ToString() => $"{this.Field}: {this.Reason}";
}
