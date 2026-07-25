# SOLID principles in Go

Unexported fields are acceptable; unexported logic is not. Hidden helper logic is
a hidden dependency: move it behind an injected service or into a cohesive
`internal/<name>` package with an exported, black-box-tested surface. Keep
interfaces narrow and owned by their consumers.
