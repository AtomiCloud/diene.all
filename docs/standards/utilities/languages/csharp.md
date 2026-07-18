# Utilities in C#/.NET

Prefer a small injectable object when behavior has policy, configuration, IO, or
nondeterminism. Use extension methods only for pure, obvious transformations that
do not hide dependencies.

```csharp
public static class StringExtensions
{
    public static string CollapseWhitespace(this string value) =>
        string.Join(' ', value.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
}
```

Keep utility APIs typed and narrow. Do not add catch-all `Helpers`, `Utils`, or
global service-locator classes. Shared capabilities graduate into a dedicated
`AtomiCloud.Diene.*` library before they are copied across applications.
