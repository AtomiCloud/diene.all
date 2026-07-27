package lifecycle

// This file encodes the shared deletion-intent vocabulary as pure policy. The
// reconciled law (controller turn 006, CR-delete adjudication): ordinary parent-CR
// deletion retains/orphans every stateful realization — it never destroys — while
// a genuinely ephemeral class (currently the diskless Dragonfly cache) may be left
// to ordinary garbage collection. Spec removal and a typed Decommission are the
// only paths that carry a destructive intent. This stays pure and policy-shaped;
// controller finalizers and concrete resource ownership land later.

// DeletionTrigger is what caused a realization to be considered for removal.
type DeletionTrigger string

// The deletion triggers. Parent-delete is an ordinary CR deletion; spec removal
// and Decommission are the two destructive intent paths.
const (
	TriggerParentDelete DeletionTrigger = "parent-delete"
	TriggerSpecRemoval  DeletionTrigger = "spec-removal"
	TriggerDecommission DeletionTrigger = "decommission"
)

// DeletionIntent is the resolved disposition for a realization.
type DeletionIntent string

// The deletion intents. Retain orphans the realization (never destroyed);
// GarbageCollect lets ordinary owner-reference GC reclaim a genuinely ephemeral or
// stateless child; Destroy actually removes external state and is reachable only
// through the two destructive triggers.
const (
	IntentRetain         DeletionIntent = "retain"
	IntentGarbageCollect DeletionIntent = "garbage-collect"
	IntentDestroy        DeletionIntent = "destroy"
)

// Destructive reports whether an intent removes durable state.
func (i DeletionIntent) Destructive() bool {
	return i == IntentDestroy
}

// Class describes a realization class for deletion classification. Stateful holds
// durable data that must survive an ordinary CR deletion; Ephemeral marks a
// genuinely disposable class (the diskless Dragonfly cache) that ordinary garbage
// collection may reclaim. A class that is neither, or that is somehow both, is
// treated conservatively as retain on parent deletion.
type Class struct {
	Name      string
	Stateful  bool
	Ephemeral bool
}

// StatefulClass builds a stateful realization class.
func StatefulClass(name string) Class {
	return Class{Name: name, Stateful: true}
}

// EphemeralClass builds a genuinely ephemeral realization class (e.g. the diskless
// Dragonfly cache).
func EphemeralClass(name string) Class {
	return Class{Name: name, Ephemeral: true}
}

// ClassifyDeletion resolves the deletion intent for a trigger against a class. Spec
// removal and Decommission always resolve to Destroy. An ordinary parent-CR
// deletion retains a stateful class, garbage-collects a purely ephemeral one, and
// otherwise fails closed to retain. Any unrecognised trigger also fails closed to
// retain so an unknown code path can never destroy durable state.
func ClassifyDeletion(trigger DeletionTrigger, class Class) DeletionIntent {
	switch trigger {
	case TriggerSpecRemoval, TriggerDecommission:
		return IntentDestroy
	case TriggerParentDelete:
		if class.Stateful {
			return IntentRetain
		}
		if class.Ephemeral {
			return IntentGarbageCollect
		}
		return IntentRetain
	default:
		return IntentRetain
	}
}
