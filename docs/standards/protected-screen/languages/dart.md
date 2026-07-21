# Flutter variant

Use a `go_router` redirect backed by the session controller. Encode `returnTo`
as an internal route, reject external URLs, and call `context.go(returnTo)` only
after authentication and authorization complete. Loading redirects use a
stable shell rather than flashing protected widgets.
