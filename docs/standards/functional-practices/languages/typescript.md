# Functional Practices in TypeScript/Bun

## Immutability

- Use `readonly` properties on interfaces
- Use spread operator for immutable updates: `{ ...obj, field: newValue }`
- Use `ReadonlyArray<T>` or `readonly T[]` for arrays
- Never mutate function arguments

```typescript
interface User {
  readonly id: string;
  readonly name: string;
  readonly email: string;
}

function updateName(user: User, name: string): User {
  return { ...user, name };
}
```

## Pure Functions

Prefer instance methods when grouping related transforms. Standalone functions are acceptable for stateless pure helpers that transform data without side effects.

> **Note:** The `updateName` function above is a standalone function for immutable transforms and is acceptable because it is stateless and has no side effects.

```typescript
// Pure instance method — all members readonly
class NameFormatter {
  constructor(private readonly suffix: string) {} // all-readonly members + no side effects → method is pure

  format(first: string, last: string): string {
    return `${first} ${last} ${this.suffix}`;
  }
}

// Impure — reads clock (external state)
class TimestampFormatter {
  format(name: string): string {
    return `${name} at ${new Date().toISOString()}`;
  }
}
```

**Rule:** Instance methods are pure if all class members are readonly and the method has no side effects.

## Total Functions

> Result type library to be determined. See error-handling skill for updates.

TypeScript domain errors use class-based Error types:

```typescript
class UserNotFound extends Error {
  constructor(readonly id: string) {
    super(`User not found: ${id}`);
    this.name = 'UserNotFound';
  }
}
```

> Result type and ROP combinator patterns for TypeScript are TBD. Once the library is pinned, this section will document `.map()`, `.mapErr()`, `.andThen()`, and `.match()` patterns.

## Folder Structure

```text
src/
  lib/                    # Domain layer — pure code
    {bounded-context}/
      {domain}/
  adapters/               # Adapter layer — impure code
    {bounded-context}/
      {domain}/
```
