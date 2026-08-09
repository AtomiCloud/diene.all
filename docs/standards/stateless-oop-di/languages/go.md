# Stateless objects and dependency injection in Go

Use structs with constructor-injected interfaces and immutable configuration.
Methods may coordinate dependencies but should not retain request-specific state.
The `cmd/<name>` package is the composition root: construct concrete adapters with
ordinary `New...` calls and pass them inward without a DI container.
