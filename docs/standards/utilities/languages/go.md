# Utilities in Go

Prefer the standard library and `golang.org/x` packages before adding helper
dependencies. A reusable helper belongs in a focused package with an exported,
black-box-tested API. Do not create generic utility bags or unexported helper
logic inside unrelated packages.
