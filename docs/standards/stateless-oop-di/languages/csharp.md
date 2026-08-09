# Stateless OOP and dependency injection in C#/.NET

Use constructor injection and keep service objects stateless. Dependencies are
readonly constructor parameters; mutable request or operation state stays in
method-local values.

```csharp
public class NoteService(INoteRepository notes, INoteSummariser summariser)
{
    public async Task<string?> Preview(string id, CancellationToken cancellationToken)
    {
        var note = await notes.Find(id, cancellationToken);
        return note is null ? null : summariser.Summarise(note.Record, 80);
    }
}
```

The base template uses explicit `new` wiring in `App/Program.cs`. Downstream ASP.NET
templates may map these same interfaces into the built-in container at the
composition root, but domain projects must not depend on the container.
