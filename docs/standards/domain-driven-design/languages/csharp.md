# Domain-driven design in C#/.NET

Keep the base four-project split aligned with the three-layer standard:

```text
Lib/       # domain records, principals, services, and owned interfaces
App/       # adapters and the explicit composition root
UnitTest/  # domain and contract tests
IntTest/   # adapters against real dependencies
```

Use immutable records for data and identified principals:

```csharp
public record NoteRecord
{
    public required string Title { get; init; }
    public required string Body { get; init; }
}

public record NotePrincipal
{
    public required string Id { get; init; }
    public required NoteRecord Record { get; init; }
}
```

The domain owns dependency interfaces. Concrete Redis, database, HTTP, or
filesystem adapters stay in `App/`. Compose implementations explicitly in the
application entry point; do not let infrastructure types leak into `Lib/`.
