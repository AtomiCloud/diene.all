# Domain-driven design in Go

Keep domain packages under `lib/` free of transport and storage dependencies.
Represent ports as small consumer-owned interfaces and inject implementations
through constructors. Use explicit structs and methods for aggregates, value
objects, and domain services; adapters translate external models at the edge.
