# Three-Layer Architecture

The domain is pure. Everything else is a plugin.

This is the architectural pattern at the heart of every AtomiCloud service. Whether the application is an HTTP API, a CLI tool, a WebSocket server, or a background worker, the structure is the same: a pure domain layer in the center, surrounded by two adapter layers that the domain neither knows about nor depends on.

---

## The Three Layers

```text
┌─────────────────────────────────────────────────────────────────┐
│                        API LAYER                                │
│   Guardrails: Type enforcement, Validation, Auth,               │
│   Mapping, Serialization/Deserialization                        │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      DOMAIN LAYER (Pure)                        │
│   Business logic, state machines, calculations                  │
│   Zero IO, zero side effects, 100% testable                     │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       DATA LAYER                                │
│   Storage: Indexes, data structures, query optimization,        │
│   connection pooling, retries, error translation                │
└─────────────────────────────────────────────────────────────────┘
```

---

## Layer Responsibilities

### API Layer — Guardrails

The API layer is the **entry point** for all external input. Its job is to protect the domain from invalid, malformed, or unauthorized requests.

**Responsibilities:**

| Concern              | What it means                                  |
| -------------------- | ---------------------------------------------- |
| **Type enforcement** | Ensure incoming data has correct types         |
| **Validation**       | Check business rules on input shape and values |
| **Auth**             | Verify caller has permission to perform action |
| **Mapping**          | Convert external format → domain format        |
| **Serialization**    | Convert domain format → external format        |

The API layer contains **zero business logic**. It is a thin adapter that:

1. Receives input in external format (JSON, CLI args, WebSocket message)
2. Validates and maps to domain format
3. Calls domain
4. Maps result to external format
5. Returns

### Domain Layer — Logic

The domain layer is the **source of truth**. All business rules live here.

**Responsibilities:**

| Concern            | What it means                                  |
| ------------------ | ---------------------------------------------- |
| **Business rules** | Invariants, constraints, calculations          |
| **State machines** | Valid transitions between states               |
| **Validation**     | Domain-level validation (not input validation) |
| **Orchestration**  | Coordinating multiple repository calls         |

**Constraints:**

- No IO — no database, no HTTP, no file system, no console
- No knowledge of outer layers — never import adapter types
- Defines interfaces for external dependencies — repository contracts

Because the domain has no IO, it is fully testable with mocked dependencies.

### Data Layer — Storage

The data layer is the **persistence boundary**. It implements the interfaces the domain defines.

**Responsibilities:**

| Concern                   | What it means                         |
| ------------------------- | ------------------------------------- |
| **Indexes**               | Design for query patterns             |
| **Data structures**       | Efficient storage format              |
| **Query optimization**    | N+1 prevention, batch loading         |
| **Connection management** | Pooling, retries, timeouts            |
| **Error translation**     | Infrastructure errors → domain errors |

The data layer catches infrastructure exceptions and translates them into domain error types. The domain never sees a `DatabaseConnectionException`.

---

## Separate Models Per Layer

Each layer has its own models. This is non-negotiable.

| Layer  | Model Type       | Optimized For               |
| ------ | ---------------- | --------------------------- |
| API    | Req/Res          | Transport (JSON, CLI args)  |
| Domain | Principal/Record | Business logic, type safety |
| Data   | Data/Entity      | Storage (ORM, indexes)      |

**Why separate models matter:**

- API format changes don't break domain tests
- Database schema changes don't break domain tests
- New transport (e.g., CLI) reuses domain without modification
- Each layer evolves independently

---

## Mappers Between Boundaries

Mappers are pure functions that translate models between layers.

**API Mapper:** External ↔ Domain

- `Req.ToDomain()` — external format → domain format
- `domain.ToRes()` — domain format → external format

**Data Mapper:** Domain ↔ Storage

- `data.ToDomain()` — storage format → domain format
- `domain.ToData()` — domain format → storage format (mutation for ORM compatibility)

**Mapper Rules:**

1. **Composable** — Higher-level mappers reuse lower-level mappers
2. **SRP grouping** — Update requests target records grouped by update rate
3. **Mutation for ToData** — Mutates existing data model (preserves ID/PK)

---

## Error Flow

Errors flow through layers as values, not exceptions.

```text
Infrastructure error (e.g., DatabaseConnectionException)
    │
    ▼
Data layer catches, maps to DomainError.StorageFailure
    │
    ▼
Domain returns Result<T, DomainError>
    │
    ▼
API layer maps to transport format (e.g., ProblemDetails for HTTP)
    │
    ▼
Response to caller
```

Each layer has its own error type. Mappers translate errors just as they translate data.

---

## Dependency Direction

**Dependency arrows point inward.**

- API layer depends on Domain (imports domain interfaces)
- Data layer depends on Domain (implements domain interfaces)
- Domain depends on nothing — it defines interfaces, others implement them

This is the heart of the plugin architecture: the domain is the core, everything else is swappable.

---

## Composition Root

All layers are wired together at the application's entry point.

This is the only place that knows about concrete types. Everything else depends on interfaces.

---

## Quick Checklist

- [ ] API layer handles: type enforcement, validation, auth, mapping, serialization
- [ ] Domain layer has zero IO
- [ ] Domain defines interfaces for external dependencies
- [ ] Each layer has its own models
- [ ] Mappers translate between layers
- [ ] Errors are values, not exceptions
- [ ] Data layer catches infrastructure errors and maps to domain errors
- [ ] API layer maps domain errors to transport errors
- [ ] All wiring at composition root
- [ ] Dependencies point inward

---

## Related Articles

- [Software Design Philosophy](../software-design-philosophy/index.md) — the "why" behind patterns
- [SOLID Principles](../solid-principles/index.md) — why layers are separated this way
- [Functional Practices](../functional-practices/index.md) — immutability, pure functions, Result types
- [Domain-Driven Design](../domain-driven-design/index.md) — modeling the domain layer
- [Stateless OOP and Dependency Injection](../stateless-oop-di/index.md) — wiring the composition root
