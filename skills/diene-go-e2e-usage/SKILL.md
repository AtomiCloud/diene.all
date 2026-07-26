---
name: diene-go-e2e-usage
description: Use the diene Go e2e harness — the compiled-artifact and in-process SIT drivers, journey parity, Garden preview targets, R14 config/env fixtures, the process and filesystem seam bindings, and the family TestHelper bundle.
---

# Diene Go e2e usage

`github.com/AtomiCloud/diene.go-e2e` is the Go family's SIT and end-to-end test
harness. It is a TEST harness: it hosts nothing, serves nothing, and is
**Bruno-free** — Bruno orchestration is sample-side, owned by the service
templates.

Every fallible call returns `(T, error)` where the error carries an RFC 9457
`problem.Problem`; recover it with
`var pe *problem.Error; errors.As(err, &pe)`.

Start with the compiling examples in `lib/e2e/example_test.go`,
`lib/preview/example_test.go`, `lib/fixture/example_test.go`, and
`testhelper/example_test.go`.

## One journey, two drivers

The point of this library is that a SIT journey runs BOTH ways:

| driver                | what it proves                                               |
| --------------------- | ------------------------------------------------------------ |
| `e2e.CompiledDriver`  | the built artifact: flags, packaging, environment contract   |
| `e2e.InProcessDriver` | the same journey with a stack trace and a debugger available |

Write the `e2e.Journey` once and run `e2e.RunParity`. It runs both and refuses
when they disagree.

Do: assert with `StdoutContains` / `StderrContains` / `StdoutExcludes`. A service's
output carries timestamps and ids; a journey demanding exact stdout gets rewritten
every release and stops being read.

Don't: expect `CompareReports` to compare captured output. It compares which steps
ran and how each one ended, on purpose — buffering, colour, and progress rendering
legitimately differ between a subprocess and an in-process run.

A non-zero exit code is a `Result`, never an error. An error means the invocation
could not be carried out at all.

`e2e.Invocation` carries no stdin, because the family's `interfaces.Terminal`
seam does not. Do not add one on the side: a field only one driver could honour
would make parity a lie.

## Seams, and which ones you have to supply

Everything nondeterministic is injected:

| seam                  | in tests                            | for real                          |
| --------------------- | ----------------------------------- | --------------------------------- |
| `interfaces.Terminal` | `testhelper.NewInMemoryTerminal()`  | `process.NewTerminal(...)` (here) |
| `interfaces.Vfs`      | `testhelper.NewInMemoryVfs(...)`    | `filesystem.NewVfs()` (here)      |
| `interfaces.System`   | `testhelper.NewInMemorySystem(...)` | `otelsdk.NewSystem()` (otel lib)  |

The harness ships the process and filesystem bindings because nothing else in the
family does. It does NOT ship a `System` binding — use the otel sibling's
`adapters/otelsdk.NewSystem()`.

Do: give `CompiledDriver` a `Filesystem` so a missing artifact is
`e2e.ProblemArtifactMissing` instead of a shell's "not found" masquerading as a
journey failure.

## Garden preview targets

`preview.Resolve` reads `E2E_PREVIEW_*` and refuses anything incomplete. It never
defaults an address: a SIT suite that silently retargets itself at localhost and
passes is worse than one that will not start.

From one `preview.Target` you get `Identity()`, `AppBlock()`, `OtelConfig()`,
`AuthConfig()`, and `APIConfig()`. SIT is the tier that turns the OTLP exporter
ON — `OtelConfig()` does exactly the D2 landscape-overlay flip to
http/protobuf on the C0 port. Endpoint validation is the otel sibling's own
validator, never a second copy.

**`preview.Schema()` currently excludes the api-engine block.** That block's
ISO 8601 duration `pattern` uses a Perl negative lookahead Go's regexp cannot
compile, so composing it is fatal at schema-compile time. `preview.APIBlock()`
exposes it for the day api-engine drops the pattern; a regression test in
`tests/unit/preview` goes red then, which is the signal to fold it back into
`preview.EngineBlocks()`.

## Fixtures

`fixture.Builder` builds the R14 three layers: full base defaults, a sparse
landscape overlay, environment last.

Do: use `WithSecret` for credentials. It writes a BLANK value into the document
and injects the real one through the environment (M4/M33), so a fixture a
consumer copies never carries a credential.

Do: use `WithList` for collections. `Bundle.Environ` renders them as C0 INDEXED
keys — `FOO__0`, `FOO__1`. `fixture.EnvKey` is the one place that encoding lives.

Don't: hand-write env var names, JSON-in-env, or comma-joined lists. That is the
exact bug class C0 froze the indexed form to kill.

Do: `Materialize` through `filesystem.NewVfs()` when a compiled artifact will read
the fixture — a subprocess cannot read an in-memory filesystem.

Use `fixture.Instant`, `fixture.Duration`, and `fixture.Zone` for wire values, not
`fmt`. They are the core-utils C0 codecs.

## The TestHelper bundle

`testhelper` re-exports the seven sibling TestHelpers that exist, under
sibling-qualified names: `ProblemAssertError`, `ConfigRequireConfig`,
`NewOtelTraceEmitter`, `AuthNewFakeIDP`, `APINewFakeBackend`,
`PresetStartPostgres`, `NewInMemoryVfs`, … The core-utils sibling ships no helper
by design, so there is nothing to re-export for it.

It also ships its own glue:

- `StartStack` — Testcontainers for the four frozen infra presets, with the
  emitted config blocks that address them. It unwinds everything it started when
  a later preset fails, so a failed boot never leaks a container.
- `NewScriptedDriver` / `EchoEntrypoint` — test your journeys before a system
  under test exists. A scripted driver that runs out of answers REFUSES rather
  than inventing a zero result.
- `AssertStep`, `AssertReport`, `AssertHarnessProblem`, … — every one proven in
  the meta tier to fail on known-bad input as well as pass on known-good.

**No fake OTLP collector, anywhere (G1).** Telemetry infrastructure is never spun
up at the integration tier; the otel interface mocks cover emission, and real
export is proven at SIT against the Garden preview environment.

## Before changing an exported API

Run `./scripts/ci/pkg-validate.sh all`. Keep v1 changes backward compatible; an
intentional breaking release needs a reviewed `/v2` module-path migration.

Before tagging, run `./scripts/validate/go-proxy-roundtrip-dryrun.sh`. The real
round trip only ever runs against a published tag that cannot be unpublished.
