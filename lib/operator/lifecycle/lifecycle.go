// Package lifecycle holds the one pure, generic reconcile framework the fleet's
// controllers consume. Three lifecycles share the framework and its deterministic
// plan/result types:
//
//   - Converge: recompute the full desired state every reconcile; a healthy state
//     yields an empty plan.
//   - IdempotentOnce: look up and adopt an existing record first, create only when
//     it is absent, then hand off once terminal success is reached.
//   - PerVersionIntent: each spec revision is a distinct intent with its own
//     terminal state; a terminally failed revision does not retry-storm, and a
//     later revision progresses independently of an earlier one.
//
// A plan is realized through a runner with exactly two modes: observe returns the
// exact would-apply plan and executes nothing; active executes each action through
// an injected narrow Executor. An invalid mode fails closed.
//
// This package is pure domain: it imports no k8s.io/* or sigs.k8s.io/* package.
package lifecycle

import (
	"context"
	"errors"
	"fmt"
	"reflect"

	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/plan"
)

// Mode selects how a plan is realized. There are exactly two modes.
type Mode string

// The two — and only two — reconcile modes.
const (
	ModeObserve Mode = "observe"
	ModeActive  Mode = "active"
)

// Valid reports whether m is one of the exactly two supported modes.
func (m Mode) Valid() bool {
	return m == ModeObserve || m == ModeActive
}

// Item is one unit of desired or observed external state, keyed by a stable
// identity and fingerprinted by a content hash. Target and Destructive describe
// how a change to the item lands in a plan.
type Item struct {
	Key         string
	DetailsHash string
	Target      plan.Target
	Destructive bool
	Metadata    plan.Metadata
}

func (it Item) create() plan.Action {
	return plan.Action{Op: plan.OpCreate, Target: it.Target, DetailsHash: it.DetailsHash, Metadata: it.Metadata}
}

func (it Item) update() plan.Action {
	return plan.Action{Op: plan.OpUpdate, Target: it.Target, DetailsHash: it.DetailsHash, Metadata: it.Metadata}
}

func (it Item) adopt() plan.Action {
	return plan.Action{Op: plan.OpAdopt, Target: it.Target, DetailsHash: it.DetailsHash, Metadata: it.Metadata}
}

func (it Item) del() plan.Action {
	return plan.Action{
		Op:          plan.OpDelete,
		Target:      it.Target,
		DetailsHash: it.DetailsHash,
		Destructive: it.Destructive,
		Metadata:    it.Metadata,
	}
}

// Converge computes the full would-apply diff between the desired items and the
// observed items every reconcile: create the missing, update the drifted, delete
// the no-longer-desired. When desired and observed already match, the plan is
// empty. Items are keyed by Item.Key; a later duplicate desired key wins.
func Converge(desired, observed []Item) plan.Plan {
	desiredByKey := index(desired)
	observedByKey := index(observed)

	var actions []plan.Action
	for _, key := range keysOf(desired) {
		want := desiredByKey[key]
		have, ok := observedByKey[key]
		switch {
		case !ok:
			actions = append(actions, want.create())
		case have.DetailsHash != want.DetailsHash:
			actions = append(actions, want.update())
		default:
			// already converged: no action for this item
		}
	}
	for _, key := range keysOf(observed) {
		if _, ok := desiredByKey[key]; !ok {
			actions = append(actions, observedByKey[key].del())
		}
	}
	return plan.Build(actions)
}

// OnceState is the durable progress of an idempotent-once lifecycle: whether a
// matching record was found (so it is adopted rather than created), and whether
// terminal success has been reached (so the lifecycle hands off and plans nothing
// more).
type OnceState struct {
	Terminal bool
}

// IdempotentOnce plans the create-once lifecycle. After terminal success it hands
// off with an empty plan. Otherwise it is lookup-first: when a matching record is
// observed it adopts that record, and only when none exists does it create one. It
// never plans a destructive action.
func IdempotentOnce(desired Item, observed *Item, state OnceState) plan.Plan {
	if state.Terminal {
		return plan.Build(nil)
	}
	if observed != nil {
		return plan.Build([]plan.Action{desired.adopt()})
	}
	return plan.Build([]plan.Action{desired.create()})
}

// IntentState is the durable progress of a per-version-intent lifecycle for a
// single revision: which revision the recorded state refers to and whether that
// revision reached a terminal state (success or failure).
type IntentState struct {
	Revision string
	Terminal bool
	Failed   bool
}

// PerVersionIntent plans the per-version-intent lifecycle for the desired
// revision. A newer revision than the recorded state always starts fresh, so a
// later revision progresses independently of an earlier one — including recovery
// after an earlier terminal failure. A revision that already reached its terminal
// state plans nothing, so a terminal failure never retry-storms.
func PerVersionIntent(desiredRevision string, desired Item, state IntentState) plan.Plan {
	if state.Revision != desiredRevision {
		return plan.Build([]plan.Action{desired.create()})
	}
	if state.Terminal {
		return plan.Build(nil)
	}
	return plan.Build([]plan.Action{desired.update()})
}

// Executor applies a single plan action against real infrastructure. It is the
// narrow port the active-mode runner drives; observe mode never touches it.
type Executor interface {
	Execute(ctx context.Context, action plan.Action) error
}

// Result is the outcome of running a plan: the mode it ran under, the exact plan
// considered, and the actions actually executed (always empty in observe mode).
type Result struct {
	Mode     Mode
	Plan     plan.Plan
	Executed []plan.Action
}

// Run realizes a plan under a mode. An invalid mode fails closed: it executes
// nothing and returns an error. Observe mode returns the exact would-apply plan
// and executes nothing, and therefore accepts a nil executor. Active mode rejects
// both a nil interface and a typed-nil executor before the first action. Otherwise
// it executes each action in deterministic order, stopping at the first error (no
// retry-storm) and reporting the actions applied so far. Plan and executor
// boundaries own separate metadata copies, so executor mutation cannot alter the
// considered plan or result.
func Run(ctx context.Context, mode Mode, pl plan.Plan, exec Executor) (Result, error) {
	if !mode.Valid() {
		return Result{}, fmt.Errorf("lifecycle: invalid mode %q", mode)
	}
	canonical := plan.Build(pl.Actions)
	res := Result{Mode: mode, Plan: canonical}
	if mode == ModeObserve {
		return res, nil
	}
	if nilExecutor(exec) {
		return res, errors.New("lifecycle: active mode requires a non-nil executor")
	}
	for _, action := range canonical.Actions {
		if err := exec.Execute(ctx, action.Clone()); err != nil {
			return res, fmt.Errorf("lifecycle: execute %s %s/%s: %w", action.Op, action.Target.Kind, action.Target.ID, err)
		}
		res.Executed = append(res.Executed, action.Clone())
	}
	return res, nil
}

func nilExecutor(exec Executor) bool {
	if exec == nil {
		return true
	}
	value := reflect.ValueOf(exec)
	switch value.Kind() {
	case reflect.Chan, reflect.Func, reflect.Interface, reflect.Map, reflect.Pointer, reflect.Slice:
		return value.IsNil()
	default:
		return false
	}
}

func index(items []Item) map[string]Item {
	byKey := make(map[string]Item, len(items))
	for _, it := range items {
		byKey[it.Key] = it
	}
	return byKey
}

// keysOf returns item keys in first-seen order so plan construction is
// deterministic before the plan's own canonical ordering.
func keysOf(items []Item) []string {
	seen := make(map[string]bool, len(items))
	keys := make([]string, 0, len(items))
	for _, it := range items {
		if !seen[it.Key] {
			seen[it.Key] = true
			keys = append(keys, it.Key)
		}
	}
	return keys
}
