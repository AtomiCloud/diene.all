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

Pure logic belongs on injected, stateless objects. Avoid static helper classes
and private logic: both hide dependencies and make behavior harder to replace or
test. Fallible domain operations use the family Result package once introduced;
do not encode expected failures as exceptions.
