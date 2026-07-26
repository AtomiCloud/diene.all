package testhelper

import (
	"context"
	"errors"
	"io"
	"sort"
	"strconv"
	"strings"
	"sync"

	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
)

// ScriptedStep is one canned answer a [ScriptedDriver] gives.
type ScriptedStep struct {
	// Result is what the driver reports for this invocation.
	Result e2e.Result
	// Err, when set, is returned instead of the result: the invocation could
	// not be carried out at all.
	Err error
}

// ScriptedDriver answers invocations from a script and records what it was
// asked.
//
// It is how a consumer tests its OWN journeys before a system under test
// exists, and how the harness tests the journey runner without a process. It is
// safe for concurrent use, because a parity run drives two drivers and a
// consumer will eventually run them in parallel.
type ScriptedDriver struct {
	label string
	mutex sync.Mutex
	steps []ScriptedStep
	calls []e2e.Invocation
}

// ErrScriptExhausted reports a scripted driver asked for more invocations than
// it was given answers for.
//
// It is an error rather than a zero result because a silent zero would let a
// journey pass on steps the script never anticipated.
var ErrScriptExhausted = errors.New("testhelper: the scripted driver has no answer left")

// NewScriptedDriver creates a driver that answers from steps in order.
func NewScriptedDriver(label string, steps ...ScriptedStep) *ScriptedDriver {
	if label == "" {
		label = "scripted"
	}
	return &ScriptedDriver{label: label, mutex: sync.Mutex{}, steps: steps, calls: nil}
}

// Name identifies the driver in reports and parity failures.
func (d *ScriptedDriver) Name() string {
	return d.label
}

// Run records the invocation and returns the next scripted answer.
func (d *ScriptedDriver) Run(_ context.Context, invocation e2e.Invocation) (e2e.Result, error) {
	d.mutex.Lock()
	defer d.mutex.Unlock()
	d.calls = append(d.calls, invocation)
	if len(d.steps) == 0 {
		return e2e.Result{}, ErrScriptExhausted
	}
	next := d.steps[0]
	d.steps = d.steps[1:]
	if next.Err != nil {
		return e2e.Result{}, next.Err
	}
	return next.Result, nil
}

// Calls returns the invocations the driver was asked to run, in order.
func (d *ScriptedDriver) Calls() []e2e.Invocation {
	d.mutex.Lock()
	defer d.mutex.Unlock()
	return append([]e2e.Invocation(nil), d.calls...)
}

// Remaining reports how many scripted answers are unused, so a test can prove
// its journey consumed the whole script rather than stopping early.
func (d *ScriptedDriver) Remaining() int {
	d.mutex.Lock()
	defer d.mutex.Unlock()
	return len(d.steps)
}

// EchoEntrypoint is an [e2e.Entrypoint] that writes back what it was given.
//
// It is the in-process half of a parity fixture: a compiled artifact that
// echoes its arguments and environment behaves identically, so a consumer can
// prove its parity wiring works before wiring in a real service.
//
// The exit code is the value of the ExitCodeVar environment variable, defaulting
// to zero, which is what lets one entrypoint drive both the passing and the
// failing halves of a journey suite.
func EchoEntrypoint(_ context.Context, invocation e2e.Invocation, stdout io.Writer, stderr io.Writer) (int, error) {
	if _, err := io.WriteString(stdout, "args: "+strings.Join(invocation.Args, " ")+"\n"); err != nil {
		return 0, err
	}
	keys := make([]string, 0, len(invocation.Env))
	for key := range invocation.Env {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	for _, key := range keys {
		if _, err := io.WriteString(stdout, "env: "+key+"="+invocation.Env[key]+"\n"); err != nil {
			return 0, err
		}
	}
	code := 0
	if raw, found := invocation.Env[ExitCodeVar]; found {
		parsed, err := strconv.Atoi(raw)
		if err != nil {
			return 0, err
		}
		code = parsed
	}
	if code != 0 {
		if _, err := io.WriteString(stderr, "exit: "+strconv.Itoa(code)+"\n"); err != nil {
			return 0, err
		}
	}
	return code, nil
}

// ExitCodeVar is the environment variable [EchoEntrypoint] reads its exit code
// from.
const ExitCodeVar = "E2E_ECHO_EXIT_CODE"

// NewEchoDriver creates an in-process driver over [EchoEntrypoint].
func NewEchoDriver(problems *e2e.Problems) (*e2e.InProcessDriver, error) {
	return e2e.NewInProcessDriver(e2e.InProcessOptions{
		Label:            "echo",
		Entrypoint:       EchoEntrypoint,
		Environment:      nil,
		WorkingDirectory: "",
		Problems:         problems,
	})
}
