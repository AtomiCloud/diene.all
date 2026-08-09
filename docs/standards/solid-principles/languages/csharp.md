# SOLID principles in C#/.NET

Interfaces live beside the domain behavior that owns them. Implementations live
at the edge and are wired in the composition root.

```csharp
public interface INoteRepository
{
    Task<NotePrincipal?> Find(string id, CancellationToken cancellationToken = default);
}

public class RedisNoteRepository(IConnectionMultiplexer redis) : INoteRepository
{
    // Adapter implementation.
}
```

Keep interfaces small and consumer-shaped. Do not use `InternalsVisibleTo`,
test-only exports, or private business logic. A responsibility that needs direct
testing is another cohesive object with a public contract.
