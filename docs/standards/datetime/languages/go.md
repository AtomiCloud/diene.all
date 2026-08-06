# Date and time in Go

Use `time.Time` for instants and normalize them with `UTC()` at boundaries.
Serialize instants with `time.RFC3339Nano`, dates as `YYYY-MM-DD`, times as
`HH:mm:ss`, durations as ISO 8601 values, and zones as IANA identifiers loaded
with `time.LoadLocation`. Never use a machine's local zone as domain state.
