# Functional practices in C#/.NET

Prefer immutable `record` types, `init` accessors, and expressions that return
new values instead of mutating inputs.

```csharp
public record User
{
    public required string Id { get; init; }
    public required string Name { get; init; }
}

var renamed = user with { Name = "New name" };
```

Behavior with policy or dependencies belongs on injected, stateless objects.
Avoid stateful or service-locator static classes and private logic; pure, obvious
transformation extensions are permitted (see the utilities standard). Fallible
domain operations use the family Result package once introduced; do not encode
expected failures as exceptions.
