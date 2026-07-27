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
is the fresh-start helper that plans minting `N+1`; `N == math.MaxInt64` is rejected
instead of wrapping. The constructor treats persisted state as untrusted and
rejects every representation that the public transition methods could not have
produced. A missing clock is also rejected: time is always injected, so every
transition and the overlap deadline are deterministic.

The persisted invariants are phase-specific:

| Phase range                                   | Generation relationship                                | Confirmation fields                                                              | Time fields                                                                               |
| --------------------------------------------- | ------------------------------------------------------ | -------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `MintPlanned` through `SmokePassed`           | `next == active + 1`, checked without overflow         | `requiredClusters` and `confirmed` are empty                                     | both timestamps are zero                                                                  |
| `FannedOut`                                   | `next == active + 1`, checked without overflow         | required set is nonempty; confirmed is a valid, duplicate-free **proper subset** | both timestamps are zero                                                                  |
| `Confirmed`                                   | `next == active + 1`, checked without overflow         | confirmed is exactly the complete required set                                   | nonzero UTC `lastConfirmationAt`; deadline is zero                                        |
| `OverlapClockStarted` through `ResmokePassed` | `next == active + 1`, checked without overflow         | confirmed is exactly the complete required set                                   | nonzero UTC last confirmation and exact UTC `overlapDeadline == lastConfirmationAt + 48h` |
| `GenerationAdvanced`                          | `active == next > 0` (the former `N+1` in both fields) | the complete required set is retained                                            | the exact UTC last-confirmation/deadline pair is retained                                 |

Blank or duplicate cluster names, confirmations outside the required set,
generation gaps/equality during an in-flight phase, stale fields from a later
phase, missing required fields, non-UTC timestamps, and forged deadlines all fail
construction. Slices are deep-copied on input and output, so caller mutation cannot
alter the validated machine state.

## The 48-hour overlap deadline

The overlap deadline is **exactly 48 hours after the last required confirmation**
(`OverlapWindow`). `Confirm` records the anchoring instant (normalized to UTC) when
the final required cluster acknowledges; `StartOverlapClock` pins
`overlapDeadline = lastConfirmation + 48h`. Saturating `time.Time` arithmetic is
rejected rather than accepting a shortened interval. Revocation is legal at or
after the deadline and refused strictly before it — the boundary is inclusive of
the deadline instant itself and exclusive one nanosecond earlier.

## Revoke predicate — fail closed

`CanRevoke(target)` judges a revocation on the current state alone, independent of
how that state was reached. It re-checks the same complete persisted-state
invariants used by `New`, so an incoherent state is never trusted. It refuses
unless **all** of the following hold:

- the phase is `OverlapClockStarted` (`ErrInvalidTransition` otherwise);
- every required cluster has confirmed, the last-confirmation time is present, and
  the required set is non-empty (`ErrInvalidState` / `ErrMissingConfirmation`);
- the deadline is the exact UTC `lastConfirmationAt + 48h` value and has elapsed
  (`ErrInvalidState` / `ErrOverlapNotElapsed`);
- `target` is the old generation `N`, never the protected active generation `N+1`
  (`ErrProtectedActiveKey`).

The last predicate plus the exact in-flight `N`/`N+1` relationship protects the
new, ledger-named key: only the generation being retired may be revoked. A missed
week remains a valid resume: an already-elapsed deadline is accepted when it is
the exact deadline derived from the persisted last confirmation, while a merely
past, forged deadline is rejected.

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
