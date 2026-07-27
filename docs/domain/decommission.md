# Decommission flow

An explicit `Decommission` CR is the only full-deletion path. Its owning
controller advances this pure flow in one strict order:

`RefsClear → Snapshotted → ExternalsDeleted → LedgerPurged → TargetDeleted → self-delete`

`RefsClear` is driven by a caller-supplied reference-blocking predicate. A nil
predicate or any remaining reference fails closed. The flow itself does no
Kubernetes, vendor, ledger-store, controller, or API I/O; adapters perform each
effect, then provide the completed proof for the next transition.

The terminal pre-purge output is a `ledger.PurgePermit`, constructed only by
`ledger.NewPurgePermit` from exactly its four required assertions: references
clear, final snapshot complete, externals deleted, and target authorization.
The flow does not reimplement or weaken that ledger capability. Proof tokens are
bound to one flow and one stage, so omitted, out-of-order, replayed, foreign, or
false completion proofs cannot produce a purge permit.

The five status facts use the shared condition vocabulary:
`RefsClear`, `Snapshotted`, `ExternalsDeleted`, `LedgerPurged`, and
`TargetDeleted`.

## Deletion boundary

Ordinary target-CR deletion retains and orphans every stateful realization; it
does not destroy external state. Re-applying the target can adopt that retained
state. Spec removal and an explicit `Decommission` are the only destructive
intent paths. The sole ordinary-CR-deletion exception is a genuinely ephemeral
diskless Dragonfly cache, which may be garbage-collected. This flow documents
that policy boundary only: concrete lifecycle, vendor, ledger, and Kubernetes
adapters belong to owning controllers.
