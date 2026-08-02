# Testing Conventions

Testing is how we know the code works. But not all tests serve the same purpose. This article defines the complete testing pyramid for AtomiCloud: what each level tests, how it tests, and when to use it.

This article builds on [Software Design Philosophy](../software-design-philosophy/index.md), [SOLID Principles](../solid-principles/index.md), and [Stateless OOP and Dependency Injection](../stateless-oop-di/index.md). The patterns in those articles -- visible dependencies, stateless services, constructor injection -- are what make testing tractable.

---

## The Test Pyramid

```text
                    ┌─────────────────────┐
                    │        E2E          │    Frontends only
                    │    (Black-box)      │    Bruno
                    └──────────┬──────────┘
                               │
                    ┌──────────┴──────────┐
                    │       Smoke         │    Artifact executes per platform
                    └──────────┬──────────┘
                               │
                    ┌──────────┴──────────┐
                    │        SIT          │    Compiled artifact, client's eye
                    │    (Black-box)      │    Bruno for HTTP APIs
                    └──────────┬──────────┘
                               │
                    ┌──────────┴──────────┐
                    │    Integration      │    CONDITIONAL — see below
                    │    (White-box)      │    Testcontainers, real deps
                    └──────────┬──────────┘
                               │
      ┌────────────────────────┼────────────────────────┐
      │                        │                        │
┌─────┴─────┐          ┌───────┴───────┐        ┌───────┴───────┐
│   Meta    │          │     Unit      │        │  Functional   │
│ TestHelper│          │  (White-box)  │        │  (Black-box)  │
│   100%    │          │  domain, 100% │        │   LSP tests   │
└───────────┘          └───────────────┘        └───────────────┘
                        `tests/unit/` hosts both
```

The canonical tiers are **unit**, **integration**, **meta**, **SIT**, **smoke** and
**E2E**. Functional and contract tests are not a separate tier — they live in
`tests/unit/` alongside the white-box unit tests, because they run at the same speed
and against the same build.

The pyramid shape is deliberate: tests at the bottom are fast, cheap, and numerous.
Tests at the top are slow, expensive, and few. Two tiers are **not** unconditional:
integration exists only where the [int-tier rule](#when-the-integration-tier-applies)
says it does, and E2E is for frontends only.

---

## Unit Tests (White-Box)

Unit tests are **white-box tests** that examine the internal implementation of a single class or function. They know about private implementation details (in our case, extracted as injectable services). They aim for **100% code coverage**.

### Unit Test Characteristics

- **Scope:** Single class or function
- **Visibility:** White-box (knows about dependencies and internal structure)
- **Speed:** Milliseconds
- **Coverage goal:** 100% of branches and paths
- **Dependencies:** All collaborators are mocked

### The AAA Pattern

Every unit test follows the same structure: **Arrange, Act, Assert**.

```typescript
it('should calculate order total', () => {
  // Arrange - set up the test
  const mockPricing = { sum: items => items.reduce((a, b) => a + b.price, 0) };
  const subject = new OrderService(mockRepo, mockPricing);
  const input = [
    { id: '1', name: 'Widget', price: 10 },
    { id: '2', name: 'Gadget', price: 20 },
  ];
  const expected = 30;

  // Act - do one thing
  const actual = subject.calculateTotal(input);

  // Assert - verify the result
  actual.should.eql(expected);
});
```

### Standard Variable Names

| Variable   | Purpose                        |
| ---------- | ------------------------------ |
| `subject`  | The class/function under test  |
| `input`    | Input parameters               |
| `expected` | Expected result                |
| `actual`   | Actual result from method call |

### Triangulation: Test Multiple Values

One test case might pass by accident. Multiple cases prove correctness.

```typescript
// WRONG - Single case, might pass by luck
it('should format status', () => {
  expect(formatStatus('pending')).toBe('Pending');
});

// RIGHT - Multiple cases prove the logic
it.each([
  ['pending', 'Pending'],
  ['running', 'Running'],
  ['completed', 'Completed'],
])('should format status (%s -> %s)', (input, expected) => {
  expect(formatStatus(input)).toBe(expected);
});
```

### Spies and Mocks for Side Effects

Pure functions don't need spies -- just check the return value. But when code has side effects (logging, I/O), use spies to verify behavior.

```typescript
// Arrange - set up collection
const logs: string[] = [];
const spyLogger = {
  log: (msg: string) => logs.push(msg),
};
const subject = new Service(spyLogger);

// Act
subject.doSomething();

// Assert - verify what was called
logs.should.eql(['expected message']);
```

### Deterministic and Fast

Tests must be:

- **Deterministic** -- No random values, no real time
- **Fast** -- No sleep, no real I/O
- **Isolated** -- No dependence on test order

```typescript
// WRONG - Uses real time (slow, non-deterministic)
it('should timeout after 1 second', async () => {
  const start = Date.now();
  await subject.doSomething();
  const elapsed = Date.now() - start;
  expect(elapsed).toBeGreaterThan(1000);
});

// RIGHT - Uses injected clock (fast, deterministic)
it('should timeout after deadline', () => {
  const clock = new FakeClock();
  const subject = new Service(clock);
  clock.tick(1001);
  subject.hasTimedOut().should.be.true();
});
```

---

## Functional Tests (Black-Box)

Functional tests are **black-box tests** that verify behavior through interfaces. They do not know about internal implementation -- only inputs, outputs, and the interface contract.

### Functional Test Characteristics

- **Scope:** Interface contract
- **Visibility:** Black-box (tests against interface, not implementation)
- **Speed:** Fast (still mocked)
- **Coverage goal:** All interface behaviors
- **Key property:** Verifies LSP (Liskov Substitution Principle)

### Why Functional Tests Matter

Functional tests validate the **interface contract**. They ensure that any implementation of the interface will behave correctly. This is the essence of the Liskov Substitution Principle.

```typescript
// The interface
interface IPaymentProcessor {
  charge(amount: Money, card: CardDetails): Result<Charge, PaymentError>;
  refund(chargeId: string): Result<Refund, PaymentError>;
}

// Functional test - tests the contract, not a specific implementation
describe('IPaymentProcessor contract', () => {
  // This test runs against ANY implementation
  function testContract(createProcessor: () => IPaymentProcessor) {
    it('should charge successfully with valid card', () => {
      const subject = createProcessor();
      const result = subject.charge(Money.usd(10.0), validCard);
      expect(result.isOk()).toBe(true);
    });

    it('should reject invalid card', () => {
      const subject = createProcessor();
      const result = subject.charge(Money.usd(10.0), invalidCard);
      expect(result.isErr()).toBe(true);
    });
  }

  // Test Stripe implementation
  describe('StripePaymentProcessor', () => {
    testContract(() => new StripePaymentProcessor(mockStripeClient));
  });

  // Test PayPal implementation
  describe('PaypalPaymentProcessor', () => {
    testContract(() => new PaypalPaymentProcessor(mockPaypalClient));
  });
});
```

### Unit vs Functional: Same Folder, Different Purpose

In practice, unit tests and functional tests often live in the same test folder. But they serve different purposes:

| Aspect      | Unit Test                  | Functional Test      |
| ----------- | -------------------------- | -------------------- |
| Knows about | Internal dependencies      | Interface only       |
| Mocks       | All collaborators          | All collaborators    |
| Validates   | Implementation correctness | Contract correctness |
| Fails when  | Code bug                   | Interface violation  |

---

## Integration Tests (White-Box, Conditional)

Integration tests verify that adapters work correctly with real external dependencies. They are **white-box tests** because they test adapter implementation with knowledge of internal structure.

### When the Integration Tier Applies

The integration tier is **not** a tier every project gets. It exists only for
**repositories you designed yourself over a dependency that exposes a DSL** — Postgres
SQL, Redis commands. There the thing under test is your query and mapping logic, so
"we test the repository" and Testcontainers is the right tool.

It does **not** apply to **small-interface dependencies**, which ship an interface plus
an implementation in the library and are proven once, out of the box:

| Dependency                        | Surface                                             | Consumer int tests                  |
| --------------------------------- | --------------------------------------------------- | ----------------------------------- |
| Telemetry                         | OTel libraries ship interfaces + in-memory mocks    | **No** — inject the mocks           |
| Block storage                     | `save`, `getLink`, `getSignedUrl` — and little else | **No** — the library is proven once |
| User-designed repo over SQL/Redis | Your own queries and mapping                        | **Yes**                             |

Writing consumer integration tests for a small-interface dependency re-proves the
library rather than your code. If a project has no user-designed repository over a
DSL-exposing dependency, it has no integration tier, and that is the correct result —
not a coverage gap.

### Integration Test Characteristics

- **Scope:** Single adapter with real external dependency
- **Visibility:** White-box (knows it's testing an adapter, sets up real DB/API)
- **Speed:** Slower (uses real databases, APIs)
- **Coverage goal:** Critical adapter paths

### Why White-Box

Integration tests in our definition test **adapters** — code that bridges our domain to external systems. When testing a `PostgresUserRepo`, you:

- Know it's a Postgres adapter (not a black box)
- Set up a real Postgres container
- Verify the SQL queries and mapping logic

This is fundamentally different from SIT/E2E which treat the system as a black box.

### Example: Repository + Database

```typescript
describe('OrderRepository integration', () => {
  let db: Database;
  let repo: OrderRepository;

  beforeAll(async () => {
    // Real database connection (Testcontainers, Docker, etc.)
    db = await Database.startTestContainer();
    repo = new OrderRepository(db);
  });

  afterAll(async () => {
    await db.stop();
  });

  it('should persist and retrieve order', async () => {
    const items = [OrderItem.create({ productId: 'widget-1', quantity: 2 })];
    const order = Order.create({ items, total: Money.usd(100) });
    await repo.save(order);
    const retrieved = await repo.getById(order.id);
    expect(retrieved).toEqual(order);
  });
});
```

Integration tests test **module by module**, not the whole system at once. A repository integration test uses a real database but still mocks external services like payment processors.

---

## Meta Tests

The **meta tier** is a third tier alongside unit and integration. Its subject is the
**TestHelper code itself** — the fakes, builders and assertion helpers a library ships
for its consumers. Test infrastructure is code, and untested test infrastructure fails
silently in the worst possible way: by passing.

### What Meta Tests Cover

- **Assert-the-asserter.** Every assertion helper is proven to **fail** on a known-bad
  case and pass on a known-good case. A helper that never fails asserts nothing.
- **Contract parity.** One shared behavioral suite per interface runs against **both**
  the real implementation and the fake, so the fake cannot drift from what it stands
  in for. Testcontainers is allowed here — these are integration-grade resources by
  nature.
- **Fixture and builder invariants.** The defaults a builder produces are valid, and
  its overrides do what they claim.

### TestHelper Is Opt-In

A library ships a TestHelper only when it genuinely helps consumers: does it expose
ports, I/O, nondeterminism or complex construction that consumers must fake, or
assertions they would otherwise repeat in every test? Record a verdict and a one-line
rationale per library. A "no" is legitimate — the guidance then lives in that
library's usage documentation instead, covering how to build a TestHelper if a real
need appears later, so it is written once rather than duplicated.

When one language finds a helper useful, ask whether the same consumer pain exists in
the sibling languages before answering for them.

### Meta Coverage Is Separate

TestHelper code is **excluded from the unit ledger** — unit coverage of test
infrastructure measures usage, not correctness. It is measured by its own meta ledger,
over TestHelper only, at **100%**, and uploaded under its own coverage flag. Where no
TestHelper exists, the meta task is a no-op and uploads nothing.

---

## SIT (System Integration Testing)

SIT tests the **entire system from a client's perspective**, driving the **compiled
artifact** rather than the source tree. Binaries and CLIs are exercised as the built
executable; HTTP APIs are exercised over the network.

**Every feature gets a SIT journey.** This is the tier that answers "does the thing we
shipped actually do the thing", so coverage of features here is per-feature and not
"critical paths only".

### SIT Characteristics

- **Scope:** Full system, through the compiled artifact
- **Visibility:** Black-box (client's eye view)
- **Speed:** Slow
- **Journey coverage:** One journey per feature
- **Tools:** **Bruno** collections for HTTP APIs; the compiled artifact directly for
  binaries and CLIs

### Why SIT?

Integration tests verify one adapter against one real dependency. SIT verifies that the entire assembled artifact works. This catches:

- Configuration errors
- Wiring mistakes
- Environment-specific issues
- Packaging and startup faults the source tree never shows

### SIT for HTTP APIs: Bruno

HTTP APIs use **Bruno collections**, run headless in CI. Bruno is the locked-in format
for SIT and for E2E — one collection format, not a different tool per tier.

```text
bru run --env sit --reporter-junit --bail
```

Collections that need scripting add `--sandbox=developer`. Collections live with the
project, versioned like any other test source, one journey per feature.

### SIT for Binaries and CLIs

Binaries and CLIs are driven as the **compiled artifact** — build it, then run it the
way a user would, asserting on exit codes and stdout/stderr. Never import the source
modules; that would make it a unit test wearing a SIT label.

### SIT Coverage: In-Process Driver Only

SIT run over the network against a deployed artifact yields no coverage, and that is
expected. Where SIT coverage **is** wanted, it comes from one place only: running the
same journeys through the **in-process driver** (`SIT_DRIVER=inprocess`), which loads
the system in the test process so the instrumentation can see it.

Two rules follow:

- Coverage numbers may be attributed to SIT **only** from an in-process run. An
  out-of-process run reports journeys passed, never a coverage percentage.
- The journeys are the same either way. The driver changes how the system is reached,
  not what is asserted.

Alongside journeys, SIT also measures response times, error rates and throughput —
but those are observations, not the pass criterion.

---

## Smoke Tests

Smoke is the narrowest tier: it proves **the artifact executes on each target
platform**. It is not a functional tier and does not overlap SIT — a passing smoke
test means the binary starts and reports itself, nothing more. Every platform the
artifact is published for gets one.

---

## E2E (End-to-End Testing)

E2E tests verify the **entire user experience**, including the frontend. These are the most expensive tests to write and maintain.

### E2E Characteristics

- **Scope:** Full stack including UI
- **Visibility:** Black-box (user's eye view)
- **Speed:** Slowest
- **Coverage goal:** Critical happy paths only

### E2E Is Only Needed for Frontend

If you are building a backend API, you do not need E2E tests. SIT covers your needs. E2E is specifically for verifying that:

- The frontend renders correctly
- User interactions work
- Frontend and backend integrate properly

### E2E Uses Bruno

E2E is the same locked-in format as SIT: **Bruno collections**, run headless. Using
one format across both black-box tiers means a journey can move between them without
being rewritten, and there is one runner to keep working in CI.

```text
bru run --env e2e --reporter-junit --bail
```

Collections that need scripting add `--sandbox=developer`.

### E2E Tests Should Be Minimal

E2E tests are brittle and expensive. Keep them to a minimum:

- Test the critical happy path
- Test the most common user journey
- Leave edge cases to lower-level tests

---

## Test Organization

Group tests logically:

Tests live under `tests/`, never colocated beside the source they exercise. Keeping
the source tree free of test files is what lets the coverage ledgers be scoped by
directory.

```text
src/
  lib/                          # unit ledger scope (100% goal)
    OrderService.ts
  adapters/                     # integration ledger scope
    OrderRepository.ts

tests/
  unit/                         # unit AND functional/contract tests together
    OrderService.test.ts        #   white-box unit
    OrderService.contract.ts    #   black-box functional/LSP
  integration/                  # only if the int-tier rule applies
    order-repository.test.ts
  meta/                         # TestHelper's own tests (100% goal)
    order-assertions.test.ts
  sit/                          # one journey per feature
    orders/                     #   Bruno collection for an HTTP API
  e2e/                          # frontends only, Bruno
    order-creation/
```

Functional and contract tests share `tests/unit/` with the white-box unit tests
deliberately: same speed, same build, same command. What separates them is what they
know, not where they live.

---

## Coverage

Coverage is **scoped per tier by an exclusion ledger**, not measured once over
everything. A single global percentage hides exactly the thing you want to know.

| Tier        | Ledger scope                         | Goal          | Notes                                      |
| ----------- | ------------------------------------ | ------------- | ------------------------------------------ |
| Unit        | Domain source only (`src/lib`)       | 100%          | TestHelper is excluded from this ledger    |
| Integration | Adapter source only (`src/adapters`) | Adapter paths | Only where the int tier applies            |
| Meta        | TestHelper source only               | 100%          | No TestHelper → no ledger, no upload       |
| SIT         | In-process driver runs only          | —             | Out-of-process runs report journeys, not % |
| Smoke / E2E | —                                    | —             | Not coverage tiers                         |

Every ledger excludes `tests/**`.

**Local thresholds are blocking; the coverage service is informational.** A build
fails locally when its tier threshold is missed. The uploaded report is for trend
watching, carrying one flag per tier (`unit`, `int`, `meta`) with carryforward so a
suite that did not run in a given build does not read as a regression. Each suite
uploads under its own flag; never merge tiers into one number.

---

## Quick Checklist

**Unit Tests:**

- [ ] AAA pattern with comments
- [ ] Variable names: subject, input, expected, actual
- [ ] Multiple test cases (triangulation)
- [ ] Spies for side effects
- [ ] Deterministic (no random, no real time)
- [ ] Fast (no sleep, no real I/O)
- [ ] 100% coverage goal

**Functional Tests:**

- [ ] Tests against interfaces, not implementations
- [ ] Same contract tests for all implementations
- [ ] Verifies LSP (Liskov Substitution Principle)

**Integration Tests (only if the int-tier rule applies):**

- [ ] There is a user-designed repository over a DSL-exposing dependency
- [ ] No consumer int tests written for small-interface deps (telemetry, block storage)
- [ ] Tests adapters with real external dependencies
- [ ] White-box: knows implementation details
- [ ] Uses real databases/APIs (Testcontainers)
- [ ] Still mocks external services outside the adapter under test
- [ ] Ledger scoped to adapter source only

**Meta Tests (where a TestHelper exists):**

- [ ] TestHelper opt-in verdict recorded with a one-line rationale
- [ ] Every assertion helper proven to fail on a known-bad case
- [ ] One shared contract suite runs against both the real implementation and the fake
- [ ] Fixture/builder invariants covered
- [ ] TestHelper excluded from the unit ledger, measured at 100% in its own

**SIT:**

- [ ] One journey per feature
- [ ] Drives the compiled artifact, not the source tree
- [ ] HTTP APIs use Bruno collections, run headless
- [ ] Coverage claimed only from the in-process driver (`SIT_DRIVER=inprocess`)

**Smoke:**

- [ ] Artifact executes on every published platform
- [ ] Proves startup only — no functional assertions

**E2E:**

- [ ] Frontends only
- [ ] Bruno, the same format as SIT
- [ ] Tests critical happy paths only

---

## Language Implementations

Language bases add their implementation guides in their own branch deltas. This
shared standard defines only the language-agnostic contract.

## Related Articles

- [Software Design Philosophy](../software-design-philosophy/index.md) -- the foundational "why"
- [SOLID Principles](../solid-principles/index.md) -- LSP for functional tests
- [Stateless OOP and Dependency Injection](../stateless-oop-di/index.md) -- designing testable code
- [Three-Layer Architecture](../three-layer-architecture/index.md) -- testing pure domain logic
