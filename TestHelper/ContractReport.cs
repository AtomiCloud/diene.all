namespace AtomiCloud.Diene.Interfaces.TestHelper;

/// <summary>One behavioural case from a seam contract suite.</summary>
/// <param name="Name">The case id.</param>
/// <param name="Failure">The reason the case failed, absent when it passed.</param>
public sealed record ContractCase(string Name, Option<string> Failure)
{
    /// <summary>Whether the case passed.</summary>
    public bool Passed => Failure.IsNone();

    /// <summary>Renders the case as <c>name: ok</c> or <c>name: reason</c>.</summary>
    public override string ToString() => $"{Name}: {Failure.GetOr("ok")}";
}

/// <summary>
/// The outcome of running one seam's shared behavioural suite against one
/// implementation. The same report shape comes back for an in-memory mock and for
/// a host-backed adapter, which is what makes contract parity checkable.
/// </summary>
public sealed class ContractReport
{
    /// <summary>Creates a report over the executed cases.</summary>
    /// <param name="seam">The seam under test.</param>
    /// <param name="cases">The executed cases, in suite order.</param>
    public ContractReport(SeamKind seam, IEnumerable<ContractCase> cases)
    {
        ArgumentNullException.ThrowIfNull(cases);
        Seam = seam;
        Cases = [.. cases];
        Failures = [.. Cases.Where(one => !one.Passed).Select(one => one.ToString())];
    }

    /// <summary>The seam under test.</summary>
    public SeamKind Seam { get; }

    /// <summary>The executed cases, in suite order.</summary>
    public IReadOnlyList<ContractCase> Cases { get; }

    /// <summary>The rendered failures, empty when the implementation conforms.</summary>
    public IReadOnlyList<string> Failures { get; }

    /// <summary>Whether every case passed.</summary>
    public bool Conformant => Failures.Count == 0;

    /// <summary>Renders the seam, the case count, and any failures.</summary>
    public override string ToString() => Conformant
        ? $"{SeamWire.Name(Seam)}: {Cases.Count} cases conformant"
        : $"{SeamWire.Name(Seam)}: {Failures.Count}/{Cases.Count} cases failed{System.Environment.NewLine}" +
          string.Join(System.Environment.NewLine, Failures);
}
