namespace AtomiCloud.DotnetBase.MetaTest;

/// <summary>
/// Container-backed meta tests share one collection so Testcontainers spin-ups are serialized
/// rather than racing for docker on an eight-core box.
/// </summary>
[CollectionDefinition("containers", DisableParallelization = true)]
public sealed class ContainerCollection;
