# Credential rotation state machine

`lib/operator/rotation` is the pure, crash-resumable state machine every
registered-fleet external dependency rotates its credentials through. It is pure
domain: it imports no Kubernetes packages and performs no vendor, Infisical, or
ledger I/O. Vendor and secret-store side effects are Phase 3 adapters that a
controller drives _from_ this machine; the machine only decides what is legal and
what happens next.

## Why two generations

Rotation issues a new credential (generation `N+1`) while the current one
(generation `N`) is still live, so consumers roll over during an overlap window
with zero downtime. Several engines cap concurrent credentials at exactly two —
the AWS access-key limit is the canonical case — so there is never a spare slot.
That single constraint drives the whole design: a rotation that crashes mid-flight
must **resume** the in-flight generation, never restart and mint a third key.

## The walk

```text
MintPlanned(N+1) -> Minted -> Committed -> SmokePassed -> FannedOut ->
Confirmed(per-cluster acks) -> OverlapClockStarted(48h from LAST confirmation) ->
Revoked(N) -> ResmokePassed -> GenerationAdvanced
```

| Transition                            | Method              | Meaning                                                                                                                                  |
| ------------------------------------- | ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `MintPlanned -> Minted`               | `Mint`              | The engine now holds both `N` and `N+1`. The new secret is not yet durable.                                                              |
| `Minted -> Committed`                 | `Commit`            | The **Fix-3 COMMIT**: the new secret is durably recorded. A mint is not a mint until it is committed.                                    |
| `Committed -> SmokePassed`            | `Smoke`             | The new credential is verified.                                                                                                          |
| `SmokePassed -> FannedOut`            | `FanOut(clusters)`  | Per-env writes / ESO refresh / consumer roll-out are requested against the required confirmation clusters.                               |
| `FannedOut -> Confirmed`              | `Confirm(cluster)`  | Per-cluster acknowledgements. The phase advances only when every required cluster has confirmed; that instant anchors the overlap clock. |
| `Confirmed -> OverlapClockStarted`    | `StartOverlapClock` | The 48h overlap deadline is pinned at `lastConfirmation + 48h`.                                                                          |
| `OverlapClockStarted -> Revoked`      | `Revoke(N)`         | Generation `N` is retired, subject to the fail-closed predicate below.                                                                   |
| `Revoked -> ResmokePassed`            | `Resmoke`           | The surviving generation still works after `N` is gone.                                                                                  |
| `ResmokePassed -> GenerationAdvanced` | `AdvanceGeneration` | Terminal. `N+1` becomes the new active generation.                                                                                       |

Every forward step is legal from exactly one source phase; any other source phase
is refused with a `TransitionError` unwrapping to `ErrInvalidTransition`. The state
is never mutated by a refused transition.

## Fix-3: commit before smoke or fan-out

`Smoke` and `FanOut` both refuse before the durable `Committed` phase with
`ErrCommitRequired`. An uncommitted vendor key can therefore never be smoked or
advertised to consumers — if the process dies before the COMMIT, the key is an
orphan (see below), not a live credential half-consumers already trust.

## Crash resume, never restart

`New(state, clock)` consumes a persisted `State` verbatim and adopts its in-flight
phase; it never resets a partially-complete rotation to the start. `Begin(N, clock)`
is the fresh-start helper that plans minting `N+1`. The constructor validates the
state structurally — known phase, non-negative generations, a duplicate-free
required cluster set, and confirmations that are a subset of that set — and fails
closed otherwise. A missing clock is rejected: time is always injected, so every
transition and the overlap deadline are deterministic.

## The 48-hour overlap deadline

The overlap deadline is **exactly 48 hours after the last required confirmation**
(`OverlapWindow`). `Confirm` records the anchoring instant (normalized to UTC) when
the final required cluster acknowledges; `StartOverlapClock` pins
`overlapDeadline = lastConfirmation + 48h`. Revocation is legal at or after the
deadline and refused strictly before it — the boundary is inclusive of the deadline
instant itself and exclusive one nanosecond earlier.

## Revoke predicate — fail closed

`CanRevoke(target)` judges a revocation on the current state alone, independent of
how that state was reached, so a resumed or corrupt state is still safe. It refuses
unless **all** of the following hold:

- the phase is `OverlapClockStarted` (`ErrInvalidTransition` otherwise);
- every required cluster has confirmed and the required set is non-empty
  (`ErrMissingConfirmation`);
- the overlap deadline is set and has elapsed (`ErrInvalidState` /
  `ErrOverlapNotElapsed`);
- `target` is the old generation `N`, never the protected active generation `N+1`
  (`ErrProtectedActiveKey`).

The last predicate is what protects the newly-active, ledger-named key: only the
generation being retired may be revoked.

## Orphan classification (the Fix-3 orphan rule)

`Reconcile(vendorKeys, committedLedger)` is the pure classification the machinery
runs on restart. The parent `ProviderAccount` root credential — held indefinitely,
the key that mints all sub-keys — reconciles what exists at the vendor against the
durable ledger:

- a key whose name carries a durable COMMIT is **protected**;
- the active ledger-named key is **always protected**, even if a bug dropped it
  from the committed name set (belt-and-braces);
- every other key was minted without a COMMIT and is an **orphan**: it is deleted
  and re-minted so the two-key limit is not consumed by a half-done mint.

Classification is pure and preserves input order; deleting and re-minting are Phase
3 adapter concerns the caller performs on the returned orphan list.

## What this machine is not

- **Rotation on/off is caller policy.** The `rotation: on|off` knob on a
  `PlatformDependency` module is honored by the controller, not by this machine; a
  module with rotation off simply never enters the walk.
- **Garden realizations and preview forks never enter this machine.** They advance
  a generation-fenced allocation through the ledger's `AdvanceGeneration` instead,
  which is already built and reviewed. This machine models only the registered-fleet
  Infisical/per-env rotation.
