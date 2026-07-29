namespace AtomiCloud.Diene.Problems;

/// <summary>Identifies the landscape, platform, service, and module owning a problem.</summary>
public sealed record ProblemIdentity(string Landscape, string Platform, string Service, string Module);

/// <summary>Combines plain ErrorPortal values with the owning service identity.</summary>
public sealed record ErrorPortalConfig(string Scheme, string Host, ProblemIdentity Identity);
