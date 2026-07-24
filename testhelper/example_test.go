package testhelper_test

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	"github.com/AtomiCloud/diene.go-interfaces/testhelper"
)

// Example shows the five deterministic in-memory seams and problem-typed
// normalization of an injected error.
func Example() {
	ctx := context.Background()
	system := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})
	vfs := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})
	terminal := testhelper.NewInMemoryTerminal()
	logger := testhelper.NewInMemoryLoggerSink()
	metrics := testhelper.NewInMemoryMetricsCollector()

	now, _ := system.NowUTC()
	exists, _ := vfs.Exists(ctx, "/")
	terminal.EnqueueResult(interfaces.TerminalOutput{Stdout: "ok"}, nil)
	output, _ := terminal.Run(ctx, interfaces.NewTerminalCommand("tool", nil, nil, nil, false, false))
	_ = logger.Emit(interfaces.NewLogRecord(now, interfaces.LogLevelInfo, "ready", nil, nil, nil))
	_ = metrics.Emit(interfaces.NewMetricRecord(now, "ready", interfaces.MetricKindGauge, 1, nil, nil))

	injected := errors.New("launch failed")
	terminal.EnqueueResult(interfaces.TerminalOutput{}, injected)
	_, err := terminal.Run(ctx, interfaces.NewTerminalCommand("tool", nil, nil, nil, false, false))
	var problemErr *problem.Error

	fmt.Println(now.Equal(time.Unix(0, 0).UTC()), exists, output.Stdout, len(logger.Records()), len(metrics.Records()), errors.As(err, &problemErr))
	// Output: true true ok 1 1 true
}
