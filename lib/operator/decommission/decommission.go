// Package decommission implements the pure, ordered proof flow for an explicit
// Decommission CR. It does not take snapshots, delete externals, purge a ledger,
// or delete Kubernetes objects. Owning controllers perform those effects and
// advance this flow only after each effect succeeds.
package decommission

import (
	"errors"
	"fmt"

	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/conditions"
	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/ledger"
)

// Errors identify fail-closed flow failures. They are deliberately distinct so
// controller adapters can translate a blocked reference check differently from a
// stale, missing, or replayed proof.
var (
	ErrReferencesBlocked = errors.New("decommission: references blocked")
	ErrInvalidProof      = errors.New("decommission: invalid proof")
	ErrOutOfOrder        = errors.New("decommission: out-of-order transition")
	ErrProofFailed       = errors.New("decommission: required operation did not complete")
)

// ReferencesBlocked is supplied by the owning controller. A true result blocks
// decommission; a nil predicate is treated as blocked. The flow itself performs
// no reference lookup or other I/O.
type ReferencesBlocked func() bool

// TargetAuthorized is supplied by the owning controller after it verifies the
// Decommission targetRef/confirm authorization. A nil predicate is unauthorized.
type TargetAuthorized func() bool

// Completion is a typed assertion from an owning controller that its preceding
// side effect completed. Its zero value is deliberately an invalid proof.
type Completion struct{ complete bool }

// Completed constructs the only valid completion assertion.
func Completed() Completion {
	return Completion{complete: true}
}

type stage uint8

const (
	stageInitial stage = iota
	stageRefsClear
	stageSnapshotted
	stageExternalsDeleted
	stagePurgePrepared
	stageLedgerPurged
	stageTargetDeleted
	stageSelfDeleteAuthorized
)

// Flow is an in-memory, I/O-free decommission ladder. Its unexported state and
// proof tokens prevent callers from skipping, reordering, or replaying steps.
// A Flow is intentionally single-use for one Decommission target.
type Flow struct {
	referencesBlocked ReferencesBlocked
	targetAuthorized  TargetAuthorized
	stage             stage
	refsClear         bool
	snapshotted       bool
	externalsDeleted  bool
}

// New constructs a new flow. Predicates are evaluated only at their respective
// gates so callers can compute the facts immediately before they are needed.
func New(referencesBlocked ReferencesBlocked, targetAuthorized TargetAuthorized) *Flow {
	return &Flow{referencesBlocked: referencesBlocked, targetAuthorized: targetAuthorized}
}

// RefsClearProof proves that no target references block decommission.
type RefsClearProof struct{ flow *Flow }

// SnapshotProof proves that the final snapshot completed after refs were clear.
type SnapshotProof struct{ flow *Flow }

// ExternalsDeletedProof proves that external realizations were deleted after the
// final snapshot.
type ExternalsDeletedProof struct{ flow *Flow }

// PurgeAuthorization carries the accepted ledger capability produced by the
// terminal pre-purge step. Permit is built only by ledger.NewPurgePermit.
type PurgeAuthorization struct {
	Permit ledger.PurgePermit
	flow   *Flow
}

// LedgerPurgedProof proves that the caller used the granted permit to purge the
// durable ledger entry.
type LedgerPurgedProof struct{ flow *Flow }

// TargetDeletedProof proves that the target CR was deleted after ledger purge.
type TargetDeletedProof struct{ flow *Flow }

// SelfDeleteAuthorization authorizes deletion of the Decommission CR itself.
// The controller adapter owns the Kubernetes API call.
type SelfDeleteAuthorization struct{ flow *Flow }

// RefsClear checks the caller-supplied blocking predicate. Missing predicates
// fail closed, as do any remaining references.
func (f *Flow) RefsClear() (RefsClearProof, error) {
	if f == nil || f.stage != stageInitial {
		return RefsClearProof{}, ErrOutOfOrder
	}
	if f.referencesBlocked == nil || f.referencesBlocked() {
		return RefsClearProof{}, ErrReferencesBlocked
	}
	f.refsClear = true
	f.stage = stageRefsClear
	return RefsClearProof{flow: f}, nil
}

// Snapshotted records successful completion of the final snapshot. completion
// must be constructed only after the owning controller's snapshot action succeeds.
func (f *Flow) Snapshotted(refs RefsClearProof, completion Completion) (SnapshotProof, error) {
	if err := f.require(refs.flow, stageRefsClear); err != nil {
		return SnapshotProof{}, err
	}
	if !completion.complete {
		return SnapshotProof{}, ErrProofFailed
	}
	f.snapshotted = true
	f.stage = stageSnapshotted
	return SnapshotProof{flow: f}, nil
}

// ExternalsDeleted records successful deletion of the target's external
// realizations after its final snapshot.
func (f *Flow) ExternalsDeleted(snapshot SnapshotProof, completion Completion) (ExternalsDeletedProof, error) {
	if err := f.require(snapshot.flow, stageSnapshotted); err != nil {
		return ExternalsDeletedProof{}, err
	}
	if !completion.complete {
		return ExternalsDeletedProof{}, ErrProofFailed
	}
	f.externalsDeleted = true
	f.stage = stageExternalsDeleted
	return ExternalsDeletedProof{flow: f}, nil
}

// PreparePurge produces the only pre-purge authorization. It delegates all four
// mandatory assertions directly to ledger.NewPurgePermit: refs clear, snapshot
// complete, externals deleted, and target authorization.
func (f *Flow) PreparePurge(externals ExternalsDeletedProof) (PurgeAuthorization, error) {
	if err := f.require(externals.flow, stageExternalsDeleted); err != nil {
		return PurgeAuthorization{}, err
	}
	targetAuthorized := f.targetAuthorized != nil && f.targetAuthorized()
	permit, err := ledger.NewPurgePermit(f.refsClear, f.snapshotted, f.externalsDeleted, targetAuthorized)
	if err != nil {
		return PurgeAuthorization{}, fmt.Errorf("decommission: prepare ledger purge: %w", err)
	}
	f.stage = stagePurgePrepared
	return PurgeAuthorization{Permit: permit, flow: f}, nil
}

// LedgerPurged records a successful physical purge performed with authorization.
func (f *Flow) LedgerPurged(authorization PurgeAuthorization, completion Completion) (LedgerPurgedProof, error) {
	if err := f.require(authorization.flow, stagePurgePrepared); err != nil {
		return LedgerPurgedProof{}, err
	}
	if !completion.complete {
		return LedgerPurgedProof{}, ErrProofFailed
	}
	f.stage = stageLedgerPurged
	return LedgerPurgedProof{flow: f}, nil
}

// TargetDeleted records a successful target-CR deletion after ledger purge.
func (f *Flow) TargetDeleted(ledgerPurged LedgerPurgedProof, completion Completion) (TargetDeletedProof, error) {
	if err := f.require(ledgerPurged.flow, stageLedgerPurged); err != nil {
		return TargetDeletedProof{}, err
	}
	if !completion.complete {
		return TargetDeletedProof{}, ErrProofFailed
	}
	f.stage = stageTargetDeleted
	return TargetDeletedProof{flow: f}, nil
}

// SelfDelete authorizes deletion of the Decommission CR after the target CR is
// gone. It intentionally does not perform the Kubernetes delete itself.
func (f *Flow) SelfDelete(targetDeleted TargetDeletedProof) (SelfDeleteAuthorization, error) {
	if err := f.require(targetDeleted.flow, stageTargetDeleted); err != nil {
		return SelfDeleteAuthorization{}, err
	}
	f.stage = stageSelfDeleteAuthorized
	return SelfDeleteAuthorization{flow: f}, nil
}

// Condition returns the stable condition vocabulary entry for a verified proof.
func (RefsClearProof) Condition() conditions.Condition {
	return conditions.True(conditions.TypeRefsClear, "ReferencesClear", "no references block decommission")
}

// Condition returns the stable condition vocabulary entry for a verified proof.
func (SnapshotProof) Condition() conditions.Condition {
	return conditions.True(conditions.TypeSnapshotted, "SnapshotComplete", "final snapshot completed")
}

// Condition returns the stable condition vocabulary entry for a verified proof.
func (ExternalsDeletedProof) Condition() conditions.Condition {
	return conditions.True(conditions.TypeExternalsDeleted, "ExternalsDeleted", "external realizations deleted")
}

// Condition returns the stable condition vocabulary entry for a verified proof.
func (LedgerPurgedProof) Condition() conditions.Condition {
	return conditions.True(conditions.TypeLedgerPurged, "LedgerPurged", "durable ledger entry purged")
}

// Condition returns the stable condition vocabulary entry for a verified proof.
func (TargetDeletedProof) Condition() conditions.Condition {
	return conditions.True(conditions.TypeTargetDeleted, "TargetDeleted", "target custom resource deleted")
}

func (f *Flow) require(proofFlow *Flow, expected stage) error {
	if f == nil || proofFlow == nil || proofFlow != f {
		return ErrInvalidProof
	}
	if f.stage != expected {
		return ErrOutOfOrder
	}
	return nil
}
