namespace AtomiCloud.Diene.E2e.Garden;

/// <summary>The service-tree coordinates encoded by a final Garden hostname.</summary>
public sealed record GardenNamespaceFixture(
    string Module,
    string Service,
    string Platform,
    string Instance,
    string Landscape,
    string Zone)
{
    /// <summary>Gets the final module.service.platform.instance.landscape.zone hostname.</summary>
    public string Hostname =>
        string.Join('.', this.Module, this.Service, this.Platform, this.Instance, this.Landscape, this.Zone);
}
