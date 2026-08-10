package testhelper_test

import (
	"fmt"
)

type recordingTestingT struct {
	helperCalls int
	fatals      []string
}

func (t *recordingTestingT) Helper() { t.helperCalls++ }

func (t *recordingTestingT) Fatalf(format string, args ...any) {
	t.fatals = append(t.fatals, fmt.Sprintf(format, args...))
}
