# Flutter variant

Use `go_router` query parameters as the source of truth. Initialize the text
controller from `GoRouterState.uri`, use `context.replace` for live edits so
history is not flooded, and use `context.push` only for committed navigation.
Cancel stale requests and expose loading, empty, and error states.
