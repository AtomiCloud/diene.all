# lib/dotnet/result implementation handoff

Date: 2026-07-22 UTC
Lane: `lib/dotnet/result`
Label: `diene-cond-5b1b11`

## Frozen child identity

The product implementation is frozen as the single conventional non-merge
commit below. This is the identity under integration review. The docs-only
commit that adds this handoff necessarily follows it: a Git commit cannot
contain its own SHA. The delivered branch HEAD and tree for that docs-only
commit are reported to the controller through `kteam send`.

| Field                   | Value                                                                     |
| ----------------------- | ------------------------------------------------------------------------- |
| Branch                  | `lib/dotnet/result`                                                       |
| Product HEAD            | `ff292a74d71c2f48802e29f5a63a6f0e64e08ca5`                                |
| Product Git tree        | `1d551680932d4604873e163d13be7ef290351182`                                |
| Sole parent             | `5049a99159672dd09ad774f62beafa21d22be312`                                |
| Commit                  | `feat(result): add typed Result and Option packages`                      |
| Docs branch HEAD        | The docs commit containing this file; exact SHA reported via `kteam send` |
| Cumulative diff vs base | 62 files changed, 2268 insertions, 708 deletions                          |
| Ancestry                | product commit has exactly one parent and it is the accepted frozen base  |

## T13 parent anchors

- Exact accepted parent commit `5049a99159672dd09ad774f62beafa21d22be312`; **Git tree `fd65b2419565cbc8753e6acc5832218574c5255d`**; sole parent `c45b068957732e7232becdac50ec17285e7191ea`.
- Proof fixture tree `b8b66f49e3a400a40e40b0c597ab6c25922adbc4` is a SEPARATE identity (parent proof only) — do NOT present it as the Git tree.
- `/home/kirin/.kteam/mrtxwcoi-07dc063f/summary.md` SHA-256 `3543287d98bb02db01f9c09286e5a8c0bf27b9b3593182f023ca1e039db38937`
- `/home/kirin/.kteam/mrtycpv9-097d3727/review.md` SHA-256 `48cf7a2faebb52d4925f1347578372759f9421852cbc6b5eb5357b2c61e8c2e3` (ends `VERDICT: ACCEPT`)
- `/home/kirin/.kteam/mrtycpv9-097d3727/markers/rb288-source-review-accepted.json` SHA-256 `3031433984f84e50d00c6d26ffb464b614975851d65cee5d6960a3fa48b6ef5a`
- `/home/kirin/.kteam/mrtzfnqc-4c7538d5/markers/rb288-dotnet-lib-exact-ci-verified.json` SHA-256 `0010041305f8aebadf9dc87692f29c5ec316e395bb8152578fe4cad0b1109a96`
- `step5-work/exec-run/c0-verify.md` SHA-256 `c879fa9bae49d790471e760b5fb2d7cde342f15bf0144e81c08058ea016e9fdc` (ends `## DONE`)
- `goals/c0-contracts.md` SHA-256 `7dd7a06279f3078a5e195d4103d01ce9fd1b30a7d88178ec37c3e6f0465c7101`

## Product shape

- Package IDs and assembly names are `AtomiCloud.Diene.Result` and
  `AtomiCloud.Diene.Result.TestHelper`; both share the root README, MIT
  license, icon, version, symbols, and vendored
  `diene-dotnet-result-usage` skill.
- Runtime namespace is deliberately plural `AtomiCloud.Diene.Results`, avoiding
  the package-tail/type-name collision while preserving the singular package
  identity.
- `Result<T, E>` and `Option<T>` are allocation-free guarded `readonly struct`
  values. Their default state throws `InvalidResultException`; wrong-variant
  extraction throws `UnwrapException` carrying the other channel's value.
- The dotnet-idiomatic surface includes Success/Failure inspection and out
  extraction, `Map`, `Then`, `MapFailure`, `Do`/`DoFailure`, `Assert`, `If`,
  `Match`, `Get`/`GetFailure`/`GetOr`, Option projection, collection combine,
  LINQ, implicit inbound conversions, and Task railway extensions.
- Carboxylic's `ExceptionFilter` policy is preserved for raw callbacks:
  matched exceptions enter the typed error channel through an explicit error
  mapper, unmatched exceptions rethrow, and Result-returning callbacks never
  capture. The Task railway includes sync/async `Assert` and `If` composition,
  plus filtered sync/async raw `Assert` and `Do` twins.
  `Result<T, Exception>` has the carboxylic-shaped no-mapper twins.
- `ResultSerial<T, E>` and `OptionSerial<T>` use System.Text.Json converters for
  the C0 tuples `["ok", value]`, `["err", error]`, `["some", value]`, and
  `["none", null]`. Direct serialization and deserialization of in-memory
  Result and Option values fail closed and instruct callers to use `ToSerial`
  and `FromSerial` with the explicit serial DUs.
- `fixtures/c0/monad-v1.json` is source-owned and versioned, with explicit
  `local-regression-only` status. Unit and host-safe integration tests consume
  it; no shared cross-language fixture or proof is claimed.
- The runtime package has zero runtime dependencies and no Problems package or
  competing Problem type.
- The FluentAssertions 7 TestHelper supplies `BeOk`, `BeErr`, `BeSome`,
  `BeNone`, and Task Result convenience assertions. The library's own tests
  reference and dogfood the packaged helper. Unit coverage excludes the helper;
  the independent meta ledger covers it at 100%.
- The old Redis/Testcontainers Note sample was replaced by a pure App consumer
  and a host-safe C0 fixture integration tier. No container was launched.

## T7 correction

The independent T7 review returned exactly two binding High findings; both are
fixed in the corrected product commit while preserving the rest of the reviewed
tree:

1. `Option<T>` now carries a dedicated `System.Text.Json` converter factory
   that rejects direct serialization and deserialization with actionable
   `ToSerial`/`FromSerial` guidance, mirroring `Result<T, E>`. Tests prove the
   positive `OptionSerial<T>` Some/None tuples and fail-closed behavior for both
   in-memory Result variants and both in-memory Option variants.
2. `Task<Result<T, E>>` now exposes sync/async Result-returning `Assert` and
   `If`, filtered sync/async raw `Assert`, and filtered async `Do`. Tests cover
   success, false/error failure, source-failure short-circuiting, mapped matched
   exceptions, unmatched rethrows, and no capture for Result-returning
   callbacks.

## Host-safe gates

All commands ran from the assigned worktree through `direnv exec .`.

| Exact command                                                                       | Result                                                                                                                             |
| ----------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `direnv exec . ./scripts/local/build.sh`                                            | Green: all five projects built in Release with 0 warnings and 0 errors.                                                            |
| `direnv exec . pls test:unit:coverage`                                              | Green: 33/33 tests; `AtomiCloud.Diene.Result` 100% line, 96.75% branch, 100% method.                                               |
| `direnv exec . pls test:int:coverage`                                               | Green: 2/2 host-safe tests; App ledger 100% line/branch/method.                                                                    |
| `direnv exec . pls test:meta:coverage`                                              | Green: 33/33 dogfood/meta tests; `AtomiCloud.Diene.Result.TestHelper` 100% line/branch/method.                                     |
| `direnv exec . ./scripts/ci/pkg-validate.sh`                                        | Green: two nupkgs + two snupkgs at 1.0.0, metadata/assets/symbol checks, and scratch restore/build against both packages.          |
| `direnv exec . ./scripts/validate/dotnet-lib-workflows.sh package`                  | Green.                                                                                                                             |
| `direnv exec . ./scripts/validate/dotnet-lib-workflows.sh publish`                  | Green.                                                                                                                             |
| `GITHUB_REF_NAME=v1.0.0 direnv exec . ./scripts/validate/dotnet-publish.sh`         | Green: committed version matched the release tag.                                                                                  |
| `env -u NUGET_API_KEY GITHUB_REF_NAME=v1.0.0 direnv exec . ./scripts/ci/publish.sh` | Expected red: stopped with `NUGET_API_KEY must be set` before setup/pack; no `artifacts/publish` directory and no publish attempt. |
| `direnv exec . bun test probes`                                                     | Green: 11 passed, 0 failed; catalog rows were not added or removed.                                                                |
| `direnv exec . pre-commit run --all-files`                                          | Green: every hook passed, including dotnetlint and treefmt.                                                                        |
| `direnv exec . git diff --check`                                                    | Green.                                                                                                                             |
| `direnv exec . git rev-list --parents -n 1 ff292a74...`                             | Product freeze showed exactly `ff292a74... 5049a991...`.                                                                           |
| `direnv exec . git status --short --branch`                                         | Clean at the final docs branch HEAD.                                                                                               |

The earlier development-loop runs exposed and resolved: missing restore assets;
compile errors while replacing the sample; one uncovered Result line (99.68%);
an initially empty integration ledger because Program was excluded; and
dotnetlint/treefmt formatting changes. Each affected final gate above was rerun
green after correction.

## Assumptions, deviations, and holds

- The upstream `AtomiCloud/carboxylic.lithium` seed was cloned read-only under
  the session coordination directory over HTTPS after the environment's SSH
  transport lacked a usable key.
- The configured commit-msg hook invokes a bare `releaser` executable, but the
  executable is absent from both the loaded default and `.#ci` shells. The
  product commit therefore used `SKIP=a-releaser-commit`; its conventional
  subject independently passed the repository Git commit-message lint, the
  release-vocabulary hooks, and the complete pre-commit suite. No source gate
  was skipped.
- The C0 fixture is intentionally local regression evidence only. Independent
  review, shared cross-language fixture/proof, integration, PR, publication,
  tagging, release, and DoD closure remain controller-owned holds.
- No push, PR, registry publication, tag, release, CyanPrint mutation matrix,
  droplet/proof, Docker/Testcontainers/k3d action, credential use, or shared
  coordination-file edit occurred.

## IMPLEMENTATION COMPLETE — INTEGRATION HELD
