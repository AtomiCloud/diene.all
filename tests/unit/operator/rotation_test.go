package operator_test

import (
	"errors"
	"math"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/rotation"
)

// anchor is a fixed, non-UTC instant so tests also prove the machine normalizes to
// UTC before pinning the overlap deadline.
var anchor = time.Date(2026, time.July, 27, 6, 0, 0, 0, time.FixedZone("UTC+2", 2*60*60))

// clock is a settable deterministic clock.
type clock struct{ t time.Time }

func (c *clock) now() time.Time { return c.t }

func newClock(t time.Time) *clock { return &clock{t: t} }

func TestBeginPlansNextGeneration(t *testing.T) {
	t.Parallel()

	m, err := rotation.Begin(7, newClock(anchor).now)
	require.NoError(t, err)
	require.Equal(t, rotation.PhaseMintPlanned, m.Phase())

	st := m.State()
	require.Equal(t, int64(7), st.ActiveGeneration)
	require.Equal(t, int64(8), st.NextGeneration)
	require.Empty(t, st.RequiredClusters)
	require.Empty(t, st.Confirmed)
}

func TestBeginRejectsNegativeGeneration(t *testing.T) {
	t.Parallel()

	_, err := rotation.Begin(-1, newClock(anchor).now)
	require.ErrorIs(t, err, rotation.ErrInvalidGeneration)
}

func TestBeginRejectsGenerationOverflow(t *testing.T) {
	t.Parallel()

	_, err := rotation.Begin(math.MaxInt64, newClock(anchor).now)
	require.ErrorIs(t, err, rotation.ErrInvalidGeneration)

	m, err := rotation.Begin(math.MaxInt64-1, newClock(anchor).now)
	require.NoError(t, err)
	require.Equal(t, int64(math.MaxInt64), m.State().NextGeneration)
}

func TestFullWalkAdvancesGeneration(t *testing.T) {
	t.Parallel()

	c := newClock(anchor)
	m, err := rotation.Begin(1, c.now)
	require.NoError(t, err)

	_, err = m.Mint()
	require.NoError(t, err)
	require.Equal(t, rotation.PhaseMinted, m.Phase())

	_, err = m.Commit()
	require.NoError(t, err)
	require.Equal(t, rotation.PhaseCommitted, m.Phase())

	_, err = m.Smoke()
	require.NoError(t, err)
	require.Equal(t, rotation.PhaseSmokePassed, m.Phase())

	_, err = m.FanOut([]string{"east", "west"})
	require.NoError(t, err)
	require.Equal(t, rotation.PhaseFannedOut, m.Phase())

	// First ack does not complete the set: still fanned out, clock unanchored.
	st, err := m.Confirm("east")
	require.NoError(t, err)
	require.Equal(t, rotation.PhaseFannedOut, m.Phase())
	require.True(t, st.LastConfirmationAt.IsZero())

	// The last required ack anchors the 48h clock at the current instant (UTC).
	c.t = anchor.Add(3 * time.Hour)
	st, err = m.Confirm("west")
	require.NoError(t, err)
	require.Equal(t, rotation.PhaseConfirmed, m.Phase())
	require.Equal(t, c.t.UTC(), st.LastConfirmationAt)

	st, err = m.StartOverlapClock()
	require.NoError(t, err)
	require.Equal(t, rotation.PhaseOverlapClockStarted, m.Phase())
	require.Equal(t, c.t.UTC().Add(rotation.OverlapWindow), st.OverlapDeadline)

	// Advance past the overlap window and revoke the OLD generation (1).
	c.t = st.OverlapDeadline.Add(time.Second)
	_, err = m.Revoke(1)
	require.NoError(t, err)
	require.Equal(t, rotation.PhaseRevoked, m.Phase())

	_, err = m.Resmoke()
	require.NoError(t, err)
	require.Equal(t, rotation.PhaseResmokePassed, m.Phase())

	st, err = m.AdvanceGeneration()
	require.NoError(t, err)
	require.Equal(t, rotation.PhaseGenerationAdvanced, m.Phase())
	require.Equal(t, int64(2), st.ActiveGeneration)
	require.Equal(t, int64(2), st.NextGeneration)
}

func TestResumeContinuesInFlightNeverRestarts(t *testing.T) {
	t.Parallel()

	// A crash left the rotation mid fan-out with one ack already recorded.
	persisted := rotation.State{
		Phase:            rotation.PhaseFannedOut,
		ActiveGeneration: 4,
		NextGeneration:   5,
		RequiredClusters: []string{"a", "b"},
		Confirmed:        []string{"a"},
	}
	c := newClock(anchor)
	m, err := rotation.New(persisted, c.now)
	require.NoError(t, err)

	// It resumes in FannedOut, not MintPlanned.
	require.Equal(t, rotation.PhaseFannedOut, m.Phase())

	// The remaining ack completes the set and continues forward.
	_, err = m.Confirm("b")
	require.NoError(t, err)
	require.Equal(t, rotation.PhaseConfirmed, m.Phase())
}

func TestNewFailsClosed(t *testing.T) {
	t.Parallel()

	valid := rotation.State{Phase: rotation.PhaseMintPlanned, ActiveGeneration: 1, NextGeneration: 2}

	t.Run("nil clock", func(t *testing.T) {
		t.Parallel()
		_, err := rotation.New(valid, nil)
		require.ErrorIs(t, err, rotation.ErrInvalidClock)
	})

	t.Run("invalid phase", func(t *testing.T) {
		t.Parallel()
		_, err := rotation.New(rotation.State{Phase: "Nonsense"}, newClock(anchor).now)
		require.ErrorIs(t, err, rotation.ErrInvalidPhase)
	})

	t.Run("negative active generation", func(t *testing.T) {
		t.Parallel()
		_, err := rotation.New(rotation.State{Phase: rotation.PhaseMintPlanned, ActiveGeneration: -1}, newClock(anchor).now)
		require.ErrorIs(t, err, rotation.ErrInvalidGeneration)
	})

	t.Run("negative next generation", func(t *testing.T) {
		t.Parallel()
		_, err := rotation.New(rotation.State{Phase: rotation.PhaseMintPlanned, NextGeneration: -1}, newClock(anchor).now)
		require.ErrorIs(t, err, rotation.ErrInvalidGeneration)
	})

	t.Run("blank required cluster", func(t *testing.T) {
		t.Parallel()
		st := valid
		st.RequiredClusters = []string{" "}
		_, err := rotation.New(st, newClock(anchor).now)
		require.ErrorIs(t, err, rotation.ErrInvalidCluster)
	})

	t.Run("duplicate required cluster", func(t *testing.T) {
		t.Parallel()
		st := valid
		st.RequiredClusters = []string{"a", "a"}
		_, err := rotation.New(st, newClock(anchor).now)
		require.ErrorIs(t, err, rotation.ErrDuplicateCluster)
	})

	t.Run("blank confirmed cluster", func(t *testing.T) {
		t.Parallel()
		st := valid
		st.RequiredClusters = []string{"a"}
		st.Confirmed = []string{""}
		_, err := rotation.New(st, newClock(anchor).now)
		require.ErrorIs(t, err, rotation.ErrInvalidCluster)
	})

	t.Run("confirmed cluster not in required set", func(t *testing.T) {
		t.Parallel()
		st := valid
		st.RequiredClusters = []string{"a"}
		st.Confirmed = []string{"b"}
		_, err := rotation.New(st, newClock(anchor).now)
		require.ErrorIs(t, err, rotation.ErrUnknownCluster)
	})

	t.Run("duplicate confirmed cluster", func(t *testing.T) {
		t.Parallel()
		st := valid
		st.RequiredClusters = []string{"a"}
		st.Confirmed = []string{"a", "a"}
		_, err := rotation.New(st, newClock(anchor).now)
		require.ErrorIs(t, err, rotation.ErrDuplicateCluster)
	})
}

func TestNewAcceptsValidResumeAtEveryPhase(t *testing.T) {
	t.Parallel()

	for _, phase := range allPhases() {
		t.Run(string(phase), func(t *testing.T) {
			t.Parallel()
			persisted := validState(phase)
			m, err := rotation.New(persisted, newClock(anchor.Add(7*24*time.Hour)).now)
			require.NoError(t, err)
			require.Equal(t, persisted, m.State())
		})
	}
}

func TestNewRejectsIncoherentGenerations(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name  string
		state rotation.State
	}{
		{
			name:  "active equals next while in flight",
			state: rotation.State{Phase: rotation.PhaseMintPlanned, ActiveGeneration: 1, NextGeneration: 1},
		},
		{
			name: "active equals next at revoke phase",
			state: func() rotation.State {
				st := validState(rotation.PhaseOverlapClockStarted)
				st.ActiveGeneration = st.NextGeneration
				return st
			}(),
		},
		{
			name:  "generation gap",
			state: rotation.State{Phase: rotation.PhaseCommitted, ActiveGeneration: 1, NextGeneration: 3},
		},
		{
			name:  "generation reversed",
			state: rotation.State{Phase: rotation.PhaseSmokePassed, ActiveGeneration: 2, NextGeneration: 1},
		},
		{
			name:  "in-flight max int cannot increment",
			state: rotation.State{Phase: rotation.PhaseMinted, ActiveGeneration: math.MaxInt64, NextGeneration: math.MaxInt64},
		},
		{
			name: "terminal retains old and next relation",
			state: func() rotation.State {
				st := validState(rotation.PhaseGenerationAdvanced)
				st.ActiveGeneration = 1
				st.NextGeneration = 2
				return st
			}(),
		},
		{
			name: "terminal zero was never reachable",
			state: func() rotation.State {
				st := validState(rotation.PhaseGenerationAdvanced)
				st.ActiveGeneration = 0
				st.NextGeneration = 0
				return st
			}(),
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			_, err := rotation.New(tc.state, newClock(anchor).now)
			require.ErrorIs(t, err, rotation.ErrInvalidGeneration)
		})
	}

	// MaxInt64 is coherent in the terminal phase: reaching it required the safe
	// in-flight relationship MaxInt64-1 -> MaxInt64 and terminal performs no add.
	terminalMax := validState(rotation.PhaseGenerationAdvanced)
	terminalMax.ActiveGeneration = math.MaxInt64
	terminalMax.NextGeneration = math.MaxInt64
	_, err := rotation.New(terminalMax, newClock(anchor).now)
	require.NoError(t, err)
}

func TestNewRejectsPhaseIncoherentConfirmationState(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name  string
		state rotation.State
		cause error
	}{
		{
			name: "required clusters before fan-out",
			state: rotation.State{
				Phase: rotation.PhaseSmokePassed, ActiveGeneration: 1, NextGeneration: 2,
				RequiredClusters: []string{"a"},
			},
			cause: rotation.ErrInvalidState,
		},
		{
			name: "confirmations before fan-out",
			state: rotation.State{
				Phase: rotation.PhaseMinted, ActiveGeneration: 1, NextGeneration: 2,
				RequiredClusters: []string{"a"}, Confirmed: []string{"a"},
			},
			cause: rotation.ErrInvalidState,
		},
		{
			name:  "fan-out requires clusters",
			state: rotation.State{Phase: rotation.PhaseFannedOut, ActiveGeneration: 1, NextGeneration: 2},
			cause: rotation.ErrNoClusters,
		},
		{
			name: "fan-out cannot retain a complete set",
			state: rotation.State{
				Phase: rotation.PhaseFannedOut, ActiveGeneration: 1, NextGeneration: 2,
				RequiredClusters: []string{"a"}, Confirmed: []string{"a"},
			},
			cause: rotation.ErrInvalidState,
		},
		{
			name: "confirmed requires the complete set",
			state: rotation.State{
				Phase: rotation.PhaseConfirmed, ActiveGeneration: 1, NextGeneration: 2,
				RequiredClusters: []string{"a", "b"}, Confirmed: []string{"a"},
				LastConfirmationAt: anchor.UTC(),
			},
			cause: rotation.ErrMissingConfirmation,
		},
		{
			name: "confirmed set cannot name another cluster",
			state: rotation.State{
				Phase: rotation.PhaseConfirmed, ActiveGeneration: 1, NextGeneration: 2,
				RequiredClusters: []string{"a"}, Confirmed: []string{"b"},
				LastConfirmationAt: anchor.UTC(),
			},
			cause: rotation.ErrUnknownCluster,
		},
		{
			name: "timestamp before confirmed",
			state: func() rotation.State {
				st := validState(rotation.PhaseFannedOut)
				st.LastConfirmationAt = anchor.UTC()
				return st
			}(),
			cause: rotation.ErrInvalidState,
		},
		{
			name: "confirmed requires timestamp",
			state: func() rotation.State {
				st := validState(rotation.PhaseConfirmed)
				st.LastConfirmationAt = time.Time{}
				return st
			}(),
			cause: rotation.ErrInvalidState,
		},
		{
			name: "last confirmation must be UTC normalized",
			state: func() rotation.State {
				st := validState(rotation.PhaseConfirmed)
				st.LastConfirmationAt = anchor
				return st
			}(),
			cause: rotation.ErrInvalidState,
		},
		{
			name: "deadline before overlap phase",
			state: func() rotation.State {
				st := validState(rotation.PhaseConfirmed)
				st.OverlapDeadline = st.LastConfirmationAt.Add(rotation.OverlapWindow)
				return st
			}(),
			cause: rotation.ErrInvalidState,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			_, err := rotation.New(tc.state, newClock(anchor).now)
			require.ErrorIs(t, err, tc.cause)
			if tc.cause != rotation.ErrUnknownCluster {
				require.ErrorIs(t, err, rotation.ErrInvalidState)
			}
		})
	}
}

func TestNewRejectsIncoherentOverlapDeadline(t *testing.T) {
	t.Parallel()

	exact := anchor.UTC().Add(rotation.OverlapWindow)
	cases := []struct {
		name  string
		state rotation.State
	}{
		{
			name: "missing deadline",
			state: func() rotation.State {
				st := validState(rotation.PhaseOverlapClockStarted)
				st.OverlapDeadline = time.Time{}
				return st
			}(),
		},
		{
			name: "past forged deadline",
			state: func() rotation.State {
				st := validState(rotation.PhaseOverlapClockStarted)
				st.OverlapDeadline = st.LastConfirmationAt.Add(-time.Hour)
				return st
			}(),
		},
		{
			name: "future forged deadline",
			state: func() rotation.State {
				st := validState(rotation.PhaseOverlapClockStarted)
				st.OverlapDeadline = exact.Add(time.Second)
				return st
			}(),
		},
		{
			name: "deadline must be UTC normalized",
			state: func() rotation.State {
				st := validState(rotation.PhaseOverlapClockStarted)
				st.OverlapDeadline = exact.In(time.FixedZone("UTC+1", 60*60))
				return st
			}(),
		},
		{
			name: "later phase cannot lose deadline",
			state: func() rotation.State {
				st := validState(rotation.PhaseRevoked)
				st.OverlapDeadline = time.Time{}
				return st
			}(),
		},
		{
			name: "terminal phase cannot forge deadline",
			state: func() rotation.State {
				st := validState(rotation.PhaseGenerationAdvanced)
				st.OverlapDeadline = exact.Add(-time.Nanosecond)
				return st
			}(),
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			_, err := rotation.New(tc.state, newClock(anchor.Add(7*24*time.Hour)).now)
			require.ErrorIs(t, err, rotation.ErrInvalidState)
		})
	}
}

func TestResumeAllowsElapsedExactDeadline(t *testing.T) {
	t.Parallel()

	state := validState(rotation.PhaseOverlapClockStarted)
	m, err := rotation.New(state, newClock(state.OverlapDeadline.Add(7*24*time.Hour)).now)
	require.NoError(t, err)
	require.NoError(t, m.CanRevoke(state.ActiveGeneration))
}

func TestCommitBeforeSmokeRefused(t *testing.T) {
	t.Parallel()

	// Smoke and fan-out both refuse before the durable COMMIT (Fix-3).
	for _, phase := range []rotation.Phase{rotation.PhaseMintPlanned, rotation.PhaseMinted} {
		m := resume(t, rotation.State{Phase: phase, ActiveGeneration: 1, NextGeneration: 2})

		_, err := m.Smoke()
		require.ErrorIs(t, err, rotation.ErrCommitRequired)

		_, err = m.FanOut([]string{"a"})
		require.ErrorIs(t, err, rotation.ErrCommitRequired)

		// State is untouched by a refused transition.
		require.Equal(t, phase, m.Phase())
	}
}

func TestFanOutRequiresSmokeAfterCommit(t *testing.T) {
	t.Parallel()

	// Committed (durable) but not yet smoked: fan-out is an invalid transition,
	// NOT a commit-required refusal.
	m := resume(t, rotation.State{Phase: rotation.PhaseCommitted, ActiveGeneration: 1, NextGeneration: 2})
	_, err := m.FanOut([]string{"a"})
	require.ErrorIs(t, err, rotation.ErrInvalidTransition)
	require.NotErrorIs(t, err, rotation.ErrCommitRequired)
}

func TestFanOutClusterValidation(t *testing.T) {
	t.Parallel()

	t.Run("empty set refused", func(t *testing.T) {
		t.Parallel()
		m := resume(t, rotation.State{Phase: rotation.PhaseSmokePassed, ActiveGeneration: 1, NextGeneration: 2})
		_, err := m.FanOut(nil)
		require.ErrorIs(t, err, rotation.ErrNoClusters)
	})

	t.Run("blank cluster refused", func(t *testing.T) {
		t.Parallel()
		m := resume(t, rotation.State{Phase: rotation.PhaseSmokePassed, ActiveGeneration: 1, NextGeneration: 2})
		_, err := m.FanOut([]string{""})
		require.ErrorIs(t, err, rotation.ErrInvalidCluster)
	})

	t.Run("duplicate cluster refused", func(t *testing.T) {
		t.Parallel()
		m := resume(t, rotation.State{Phase: rotation.PhaseSmokePassed, ActiveGeneration: 1, NextGeneration: 2})
		_, err := m.FanOut([]string{"a", "a"})
		require.ErrorIs(t, err, rotation.ErrDuplicateCluster)
	})
}

func TestConfirmValidation(t *testing.T) {
	t.Parallel()

	base := rotation.State{
		Phase:            rotation.PhaseFannedOut,
		ActiveGeneration: 1,
		NextGeneration:   2,
		RequiredClusters: []string{"a", "b"},
	}

	t.Run("blank cluster refused", func(t *testing.T) {
		t.Parallel()
		m := resume(t, base)
		_, err := m.Confirm("  ")
		require.ErrorIs(t, err, rotation.ErrInvalidCluster)
	})

	t.Run("unknown cluster refused", func(t *testing.T) {
		t.Parallel()
		m := resume(t, base)
		_, err := m.Confirm("c")
		require.ErrorIs(t, err, rotation.ErrUnknownCluster)
	})

	t.Run("duplicate ack is an idempotent no-op", func(t *testing.T) {
		t.Parallel()
		m := resume(t, base)
		_, err := m.Confirm("a")
		require.NoError(t, err)
		st, err := m.Confirm("a")
		require.NoError(t, err)
		require.Equal(t, rotation.PhaseFannedOut, m.Phase())
		require.Equal(t, []string{"a"}, st.Confirmed)
	})

	t.Run("confirm outside fan-out refused", func(t *testing.T) {
		t.Parallel()
		m := resume(t, rotation.State{Phase: rotation.PhaseCommitted, ActiveGeneration: 1, NextGeneration: 2})
		_, err := m.Confirm("a")
		require.ErrorIs(t, err, rotation.ErrInvalidTransition)
	})
}

func TestOverlapDeadlineBoundary(t *testing.T) {
	t.Parallel()

	// last confirmation at the anchor -> deadline is anchor + 48h exactly.
	deadline := anchor.UTC().Add(rotation.OverlapWindow)

	cases := []struct {
		name    string
		now     time.Time
		allowed bool
	}{
		{name: "one nanosecond before deadline", now: deadline.Add(-time.Nanosecond), allowed: false},
		{name: "exactly at deadline", now: deadline, allowed: true},
		{name: "after deadline", now: deadline.Add(time.Nanosecond), allowed: true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			c := newClock(tc.now)
			m, err := rotation.New(rotation.State{
				Phase:              rotation.PhaseOverlapClockStarted,
				ActiveGeneration:   1,
				NextGeneration:     2,
				RequiredClusters:   []string{"a"},
				Confirmed:          []string{"a"},
				LastConfirmationAt: anchor.UTC(),
				OverlapDeadline:    deadline,
			}, c.now)
			require.NoError(t, err)

			err = m.CanRevoke(1)
			if tc.allowed {
				require.NoError(t, err)
			} else {
				require.ErrorIs(t, err, rotation.ErrOverlapNotElapsed)
			}
		})
	}
}

func TestStartOverlapClockRequiresConfirmedPhase(t *testing.T) {
	t.Parallel()

	m := resume(t, rotation.State{
		Phase:            rotation.PhaseFannedOut,
		ActiveGeneration: 1,
		NextGeneration:   2,
		RequiredClusters: []string{"a"},
	})
	_, err := m.StartOverlapClock()
	require.ErrorIs(t, err, rotation.ErrInvalidTransition)
}

func TestStartOverlapClockRejectsArithmeticOverflowWithoutMutation(t *testing.T) {
	t.Parallel()

	// time.Time stores Unix seconds with this year-1-to-1970 offset. Starting
	// one hour below its internal ceiling makes Add(48h) saturate, which must not
	// collapse the promised overlap window to one hour.
	const unixToInternal = int64(62_135_596_800)
	lastConfirmation := time.Unix(math.MaxInt64-unixToInternal-60*60, 0).UTC()
	confirmed := rotation.State{
		Phase:              rotation.PhaseConfirmed,
		ActiveGeneration:   1,
		NextGeneration:     2,
		RequiredClusters:   []string{"a"},
		Confirmed:          []string{"a"},
		LastConfirmationAt: lastConfirmation,
	}
	m := resume(t, confirmed)

	_, err := m.StartOverlapClock()
	require.ErrorIs(t, err, rotation.ErrInvalidState)
	require.Equal(t, confirmed, m.State())

	forged := confirmed
	forged.Phase = rotation.PhaseOverlapClockStarted
	forged.OverlapDeadline = lastConfirmation.Add(rotation.OverlapWindow)
	_, err = rotation.New(forged, newClock(lastConfirmation).now)
	require.ErrorIs(t, err, rotation.ErrInvalidState)
}

func TestConfirmRejectsZeroClockWithoutMutation(t *testing.T) {
	t.Parallel()

	m, err := rotation.New(rotation.State{
		Phase:            rotation.PhaseFannedOut,
		ActiveGeneration: 1,
		NextGeneration:   2,
		RequiredClusters: []string{"a"},
	}, func() time.Time { return time.Time{} })
	require.NoError(t, err)

	_, err = m.Confirm("a")
	require.ErrorIs(t, err, rotation.ErrInvalidState)
	require.Equal(t, rotation.PhaseFannedOut, m.Phase())
	require.Empty(t, m.State().Confirmed)
}

func TestRevokePredicateFailsClosed(t *testing.T) {
	t.Parallel()

	deadline := anchor.UTC().Add(rotation.OverlapWindow)
	ready := rotation.State{
		Phase:              rotation.PhaseOverlapClockStarted,
		ActiveGeneration:   1,
		NextGeneration:     2,
		RequiredClusters:   []string{"a", "b"},
		Confirmed:          []string{"a", "b"},
		LastConfirmationAt: anchor.UTC(),
		OverlapDeadline:    deadline,
	}
	past := deadline.Add(time.Hour)

	t.Run("wrong phase refused", func(t *testing.T) {
		t.Parallel()
		m := resumeAt(t, rotation.State{Phase: rotation.PhaseConfirmed, ActiveGeneration: 1, NextGeneration: 2, RequiredClusters: []string{"a"}, Confirmed: []string{"a"}, LastConfirmationAt: anchor.UTC()}, past)
		_, err := m.Revoke(1)
		require.ErrorIs(t, err, rotation.ErrInvalidTransition)
	})

	t.Run("overlap window not elapsed refused", func(t *testing.T) {
		t.Parallel()
		m := resumeAt(t, ready, deadline.Add(-time.Hour))
		_, err := m.Revoke(1)
		require.ErrorIs(t, err, rotation.ErrOverlapNotElapsed)
	})

	t.Run("revoking the protected active key refused", func(t *testing.T) {
		t.Parallel()
		m := resumeAt(t, ready, past)
		// Generation 2 (N+1) is the newly-active, ledger-named, protected key.
		_, err := m.Revoke(2)
		require.ErrorIs(t, err, rotation.ErrProtectedActiveKey)
		// An unrelated generation is equally refused (only the old gen is legal).
		_, err = m.Revoke(99)
		require.ErrorIs(t, err, rotation.ErrProtectedActiveKey)
		// The state is left intact by the refusal.
		require.Equal(t, rotation.PhaseOverlapClockStarted, m.Phase())
	})

	t.Run("legal revoke of the old generation succeeds", func(t *testing.T) {
		t.Parallel()
		m := resumeAt(t, ready, past)
		_, err := m.Revoke(1)
		require.NoError(t, err)
		require.Equal(t, rotation.PhaseRevoked, m.Phase())
	})
}

func TestInvalidTransitions(t *testing.T) {
	t.Parallel()

	// Each forward step is legal from exactly one source phase. Drive every step
	// from a wrong phase and assert an invalid-transition refusal.
	steps := []struct {
		name string
		from rotation.Phase
		call func(m *rotation.Machine) error
	}{
		{name: "mint", from: rotation.PhaseMintPlanned, call: func(m *rotation.Machine) error { _, e := m.Mint(); return e }},
		{name: "commit", from: rotation.PhaseMinted, call: func(m *rotation.Machine) error { _, e := m.Commit(); return e }},
		{name: "resmoke", from: rotation.PhaseRevoked, call: func(m *rotation.Machine) error { _, e := m.Resmoke(); return e }},
		{name: "advance", from: rotation.PhaseResmokePassed, call: func(m *rotation.Machine) error { _, e := m.AdvanceGeneration(); return e }},
	}
	for _, step := range steps {
		for _, phase := range allPhases() {
			if phase == step.from {
				continue
			}
			m := resume(t, validState(phase))
			err := step.call(m)
			require.ErrorIsf(t, err, rotation.ErrInvalidTransition, "%s from %s", step.name, phase)
		}
	}
}

func TestReconcileClassifiesOrphans(t *testing.T) {
	t.Parallel()

	vendor := []rotation.VendorKey{
		{ID: "id-active", Name: "gen-2"},    // active, protected
		{ID: "id-committed", Name: "gen-1"}, // committed, protected
		{ID: "id-orphan", Name: "gen-3"},    // minted, never committed
		{ID: "id-nameless", Name: ""},       // minted, crashed before naming
	}
	ledger := rotation.CommittedLedger{
		Names:     []string{"gen-1", "gen-2"},
		ActiveKey: "gen-2",
	}

	orphans := rotation.Reconcile(vendor, ledger)
	require.Len(t, orphans, 2)
	// Input order is preserved.
	require.Equal(t, "id-orphan", orphans[0].Key.ID)
	require.Equal(t, "id-nameless", orphans[1].Key.ID)
	require.NotEmpty(t, orphans[0].Reason)
}

func TestReconcileProtectsActiveKeyEvenIfAbsentFromCommitted(t *testing.T) {
	t.Parallel()

	// Belt-and-braces: the active key is protected even if a bug dropped it from
	// the committed name set. It must never be classified an orphan.
	vendor := []rotation.VendorKey{{ID: "id-active", Name: "gen-2"}}
	orphans := rotation.Reconcile(vendor, rotation.CommittedLedger{Names: nil, ActiveKey: "gen-2"})
	require.Empty(t, orphans)
}

func TestReconcileEmptyInputs(t *testing.T) {
	t.Parallel()

	require.Empty(t, rotation.Reconcile(nil, rotation.CommittedLedger{}))
}

func TestStateReturnsCopy(t *testing.T) {
	t.Parallel()

	m := resume(t, rotation.State{
		Phase:            rotation.PhaseFannedOut,
		ActiveGeneration: 1,
		NextGeneration:   2,
		RequiredClusters: []string{"a", "b"},
		Confirmed:        []string{"a"},
	})
	snapshot := m.State()
	snapshot.RequiredClusters[0] = "mutated"
	snapshot.Confirmed[0] = "mutated"

	fresh := m.State()
	require.Equal(t, []string{"a", "b"}, fresh.RequiredClusters)
	require.Equal(t, []string{"a"}, fresh.Confirmed)
}

func TestMachineDoesNotAliasCallerSlices(t *testing.T) {
	t.Parallel()

	persisted := validState(rotation.PhaseFannedOut)
	m := resume(t, persisted)
	persisted.RequiredClusters[0] = "mutated"
	persisted.Confirmed[0] = "mutated"
	require.Equal(t, []string{"a", "b"}, m.State().RequiredClusters)
	require.Equal(t, []string{"a"}, m.State().Confirmed)

	fanOutMachine := resume(t, validState(rotation.PhaseSmokePassed))
	clusters := []string{"east", "west"}
	_, err := fanOutMachine.FanOut(clusters)
	require.NoError(t, err)
	clusters[0] = "mutated"
	require.Equal(t, []string{"east", "west"}, fanOutMachine.State().RequiredClusters)
}

func TestPhaseValid(t *testing.T) {
	t.Parallel()

	require.True(t, rotation.PhaseCommitted.Valid())
	require.True(t, rotation.PhaseGenerationAdvanced.Valid())
	require.False(t, rotation.Phase("nope").Valid())
}

func TestTransitionErrorMessageAndUnwrap(t *testing.T) {
	t.Parallel()

	m := resume(t, rotation.State{Phase: rotation.PhaseMintPlanned, ActiveGeneration: 1, NextGeneration: 2})
	_, err := m.Commit()
	require.Error(t, err)

	var te *rotation.TransitionError
	require.True(t, errors.As(err, &te))
	require.Equal(t, "commit", te.Operation)
	require.Equal(t, rotation.PhaseMintPlanned, te.From)
	require.Contains(t, err.Error(), "cannot commit")
	require.ErrorIs(t, err, rotation.ErrInvalidTransition)
}

func allPhases() []rotation.Phase {
	return []rotation.Phase{
		rotation.PhaseMintPlanned,
		rotation.PhaseMinted,
		rotation.PhaseCommitted,
		rotation.PhaseSmokePassed,
		rotation.PhaseFannedOut,
		rotation.PhaseConfirmed,
		rotation.PhaseOverlapClockStarted,
		rotation.PhaseRevoked,
		rotation.PhaseResmokePassed,
		rotation.PhaseGenerationAdvanced,
	}
}

func validState(phase rotation.Phase) rotation.State {
	state := rotation.State{
		Phase:            phase,
		ActiveGeneration: 1,
		NextGeneration:   2,
	}

	switch phase {
	case rotation.PhaseFannedOut:
		state.RequiredClusters = []string{"a", "b"}
		state.Confirmed = []string{"a"}
	case rotation.PhaseConfirmed:
		state.RequiredClusters = []string{"a", "b"}
		state.Confirmed = []string{"b", "a"}
		state.LastConfirmationAt = anchor.UTC()
	case rotation.PhaseOverlapClockStarted, rotation.PhaseRevoked, rotation.PhaseResmokePassed:
		state.RequiredClusters = []string{"a", "b"}
		state.Confirmed = []string{"b", "a"}
		state.LastConfirmationAt = anchor.UTC()
		state.OverlapDeadline = anchor.UTC().Add(rotation.OverlapWindow)
	case rotation.PhaseGenerationAdvanced:
		state.ActiveGeneration = 2
		state.NextGeneration = 2
		state.RequiredClusters = []string{"a", "b"}
		state.Confirmed = []string{"b", "a"}
		state.LastConfirmationAt = anchor.UTC()
		state.OverlapDeadline = anchor.UTC().Add(rotation.OverlapWindow)
	}

	return state
}

// resume constructs a machine from persisted state with a clock pinned at the
// anchor instant.
func resume(t *testing.T, state rotation.State) *rotation.Machine {
	t.Helper()
	m, err := rotation.New(state, newClock(anchor).now)
	require.NoError(t, err)
	return m
}

// resumeAt constructs a machine from persisted state with a clock pinned at now.
func resumeAt(t *testing.T, state rotation.State, now time.Time) *rotation.Machine {
	t.Helper()
	m, err := rotation.New(state, newClock(now).now)
	require.NoError(t, err)
	return m
}
