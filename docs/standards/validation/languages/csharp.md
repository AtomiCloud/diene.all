# Validation in C#/.NET

Validate at the boundary, then pass typed values into domain behavior. Use native
guard APIs for simple invariants and a schema/validator object for structured input.

```csharp
public sealed record CreateNote
{
    public required string Title { get; init; }
    public required string Body { get; init; }
}

ArgumentException.ThrowIfNullOrWhiteSpace(command.Title);
```

Downstream services that adopt FluentValidation pin it through Central Package
Management and translate failures into the family Problem/Result contracts. Do not
return ad hoc dictionaries or throw expected validation failures across a public
boundary.
