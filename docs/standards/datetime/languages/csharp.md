# Date and time in C#/.NET

Use the .NET types that encode the intended semantic directly:

- `DateOnly` for calendar dates.
- `TimeOnly` for wall-clock times without a date.
- `DateTimeOffset` for instants and timestamps.
- `TimeSpan` for in-process durations.
- `TimeZoneInfo` with IANA zone identifiers for timezone conversion.

```csharp
var createdAt = DateTimeOffset.UtcNow;
var billingDate = new DateOnly(2026, 7, 18);
var retryAfter = TimeSpan.FromMinutes(5);
var singapore = TimeZoneInfo.FindSystemTimeZoneById("Asia/Singapore");
var localCreatedAt = TimeZoneInfo.ConvertTime(createdAt, singapore);
```

Persist instants as UTC and serialize them as RFC 3339. Do not use local or
`Unspecified` `DateTime` values for wire contracts. Use ISO 8601 strings for
dates, times, and durations exactly as defined by the parent standard.
