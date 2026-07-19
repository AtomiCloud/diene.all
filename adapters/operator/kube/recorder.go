package kube

import (
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/tools/record"
)

// Recorder is the event-emission port controllers use to publish reconciliation
// outcomes (converged, blast-brake tripped, owned-name conflict) as Kubernetes
// events, without depending on the concrete client-go recorder.
type Recorder interface {
	Event(object runtime.Object, eventtype, reason, message string)
}

// EventRecorder adapts a client-go record.EventRecorder to the Recorder port.
type EventRecorder struct {
	recorder record.EventRecorder
}

// NewEventRecorder wraps a client-go event recorder as a Recorder.
func NewEventRecorder(recorder record.EventRecorder) EventRecorder {
	return EventRecorder{recorder: recorder}
}

// Event emits a Kubernetes event against object.
func (e EventRecorder) Event(object runtime.Object, eventtype, reason, message string) {
	e.recorder.Event(object, eventtype, reason, message)
}
