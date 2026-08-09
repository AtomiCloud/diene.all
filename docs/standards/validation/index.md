# Data Validation

Validation ensures data meets expected constraints before processing. This guide defines validation patterns, when to use them, and how to implement them across AtomiCloud projects.

This article builds on [Three-Layer Architecture](../three-layer-architecture/index.md) and [Error Handling](../functional-practices/index.md). Validation happens at layer boundaries, and validation errors follow error-handling conventions.

---

## Why Use Validation Libraries

### Reduce Boilerplate

Without libraries, validation code is repetitive:

```typescript
// ANTI-PATTERN - manual validation, lots of boilerplate. Note that it also
// throws for expected-invalid input, which this standard forbids; the fix is
// a schema's non-throwing parse lifted into Result, shown below.
// @ts-ignore — intentionally incomplete example for illustration
function validateUser(input: unknown): User {
  if (typeof input !== 'object' || input === null) {
    throw new Error('Invalid input');
  }
  // Note: TypeScript still types 'input' as object after the guard,
  // so property access would error. This is intentional to show the "bad" pattern.
  if (typeof (input as any).name !== 'string' || (input as any).name.length < 2) {
    throw new Error('Name must be at least 2 characters');
  }
  if (!(input as any).email.includes('@')) {
    throw new Error('Invalid email');
  }
  // ... more checks
  return input as User;
}
```

With a library, it's declarative:

```typescript
// Zod schema - concise, type-safe
const UserSchema = z.object({
  name: z.string().min(2),
  email: z.string().email(),
});

// Expected-invalid input is a VALUE, not an exception. Use the non-throwing
// entry point and lift it into the project Result type.
const parsed = UserSchema.safeParse(input);
const user = parsed.success ? Result.ok(parsed.data) : Result.err(ValidationError.from(parsed.error));
```

Invalid external input is expected — a client can always send a bad email. Per
[functional practices](../functional-practices/index.md) and the
[three-layer architecture](../three-layer-architecture/index.md), expected
failures are Result values, so validation never uses the throwing `parse`
entry point. Reserve throwing for genuinely exceptional conditions the caller
cannot be expected to handle.

### Reduce Tests

Validation libraries are battle-tested. You don't need to test that:

- Email validation works correctly
- Minimum/maximum constraints are enforced
- Required fields are checked
- Type coercion handles edge cases

You only test your custom validators.

### Type Safety

Schemas can infer types, ensuring your validation and types never drift:

```typescript
const UserSchema = z.object({
  name: z.string(),
  age: z.number().int().positive(),
});

type User = z.infer<typeof UserSchema>; // { name: string; age: number }
```

---

## Validation at Boundaries

### Input Validation

Validate all external input at the API boundary (controllers, adapters):

```text
External World → [Validate] → Controller → Domain
```

**What to validate:**

- Presence (required fields)
- Format (email, URL, date format)
- Range (min/max numbers, string length)
- Type (string, number, boolean)
- Structure (nested objects, arrays)

**What NOT to validate:**

- Business rules (belongs in domain)
- Cross-field dependencies (often domain invariants)
- Existence checks (database queries)

### Domain Invariants

Business rules live in the domain layer:

```csharp
// Domain invariant in entity. The constructor is private and the smart
// constructor returns a Result, so a violated invariant is a value the caller
// must handle -- not an exception thrown across the layer boundary.
public record Order
{
    public Money Total { get; init; }

    private Order(Money total) => Total = total;

    public static Result<Order> Create(Money total) =>
        total.Amount < 0
            ? Result<Order>.Err(new NegativeOrderTotal(total))
            : Result<Order>.Ok(new Order(total));
}
```

A domain invariant that external input can violate is still an _expected_
failure: the client sent a negative total, and the API must answer with a 422
rather than crash. It therefore returns a Result exactly like input validation
does. The difference between the two is **where the rule lives and what it
means**, not whether it throws.

### Input Validation vs Domain Invariants

| Aspect       | Input Validation                    | Domain Invariants                    |
| ------------ | ----------------------------------- | ------------------------------------ |
| Location     | API boundary                        | Domain constructors/methods          |
| Purpose      | Sanitize external input             | Enforce business rules               |
| Examples     | Email format, required              | Order total >= 0, status transitions |
| Mechanism    | Non-throwing parse → `Result`       | Smart constructor → `Result`         |
| Failure type | `ValidationError` in the `Err` case | Domain error in the `Err` case       |
| Mapped to    | 400                                 | 422                                  |
| Library      | Validation library                  | Domain code                          |

Both columns return the project `Result` type. Neither throws for expected
invalid input; the API layer maps the `Err` case to its status code. Exceptions
remain for the genuinely exceptional — a lost database connection, a corrupt
config — never for a client sending bad data.

---

## Validation Patterns

### Schema Validation

Define a schema, parse input against it:

```typescript
const CreateOrderSchema = z.object({
  items: z
    .array(
      z.object({
        productId: z.string().uuid(),
        quantity: z.number().int().positive(),
      }),
    )
    .min(1),
  shippingAddress: z.object({
    street: z.string(),
    city: z.string(),
    zipCode: z.string().regex(/^\d{5}$/),
  }),
});

// Both outcomes are represented as values. Nothing throws.
const result = CreateOrderSchema.safeParse(requestBody);
const order: Result<CreateOrder, ValidationError> = result.success
  ? Result.ok(result.data)
  : Result.err(ValidationError.from(result.error));
```

### Transform and Validate

Parse, then transform:

```typescript
const SearchSchema = z.object({
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().max(100).default(20),
  query: z.string().trim().optional(),
});

// "page=2&limit=50" -> { page: 2, limit: 50, query: undefined }
```

### Cross-Field Validation

Validate relationships between fields:

```go
type Registration struct {
    Password     string `validate:"required,min=8"`
    Confirmation string `validate:"required,eqfield=Password"`
}
```

---

## Error Messages

Return meaningful, actionable errors:

```json
{
  "errors": {
    "email": ["Must be a valid email address"],
    "age": ["Must be at least 18"],
    "items[0].quantity": ["Must be greater than 0"]
  }
}
```

**Guidelines:**

- Field-specific errors (not just "validation failed")
- Actionable messages (tell user what to fix)
- Don't expose internal structure
- Use consistent format

---

## Quick Checklist

**Input Validation:**

- [ ] All external input validated at boundary
- [ ] Required fields checked
- [ ] Format validation (email, URL, etc.)
- [ ] Range constraints (min/max)
- [ ] Type safety from schema
- [ ] Meaningful error messages

**Domain Invariants:**

- [ ] Business rules in domain layer
- [ ] Smart constructors enforce invariants and return `Result`
- [ ] Meaningful domain errors carried in the `Err` value

**General:**

- [ ] Use validation library, not hand-coded
- [ ] Don't test library validators
- [ ] Parse, don't validate
- [ ] No throwing entry point (`parse`) for expected-invalid input — `safeParse` lifted into `Result`
- [ ] Exceptions reserved for the genuinely exceptional, never for client input

---

## Language Implementations

Language bases add their implementation guides in their own branch deltas. This
shared standard defines only the language-agnostic contract.

- [C#/.NET](languages/csharp.md)

## Related Articles

- [Three-Layer Architecture](../three-layer-architecture/index.md) — Where validation happens
- [Error Handling](../functional-practices/index.md) — Returning validation errors
- [Domain Modeling](../domain-driven-design/index.md) — Domain invariants
