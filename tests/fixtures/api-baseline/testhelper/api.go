package testhelper

import (
	"context"
	"time"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
)

type InMemorySystemOptions struct {
	Environment map[string]string
	Directory   string
	Now         time.Time
}
type InMemorySystem struct{}

func NewInMemorySystem(InMemorySystemOptions) *InMemorySystem      { return nil }
func (*InMemorySystem) EnqueueEnvironmentResult(*string, error)    {}
func (*InMemorySystem) EnqueueDirectoryResult(string, error)       {}
func (*InMemorySystem) EnqueueClockResult(time.Time, error)        {}
func (*InMemorySystem) EnqueueDelayResult(error)                   {}
func (*InMemorySystem) Environment(string) (*string, error)        { return nil, nil }
func (*InMemorySystem) CurrentDirectory() (string, error)          { return "", nil }
func (*InMemorySystem) NowUTC() (time.Time, error)                 { return time.Time{}, nil }
func (*InMemorySystem) Delay(context.Context, time.Duration) error { return nil }
func (*InMemorySystem) RequestedDelays() []time.Duration           { return nil }
func (*InMemorySystem) SetEnvironment(string, string)              {}
func (*InMemorySystem) SetDirectory(string)                        {}
func (*InMemorySystem) SetNow(time.Time)                           {}

type InMemoryVfsOptions struct {
	Files       map[string][]byte
	Directories []string
}
type InMemoryVfs struct{}

func NewInMemoryVfs(InMemoryVfsOptions) *InMemoryVfs                   { return nil }
func (*InMemoryVfs) EnqueueExistsResult(bool, error)                   {}
func (*InMemoryVfs) EnqueueReadBytesResult([]byte, error)              {}
func (*InMemoryVfs) EnqueueReadTextResult(string, error)               {}
func (*InMemoryVfs) EnqueueWriteBytesResult(error)                     {}
func (*InMemoryVfs) EnqueueWriteTextResult(error)                      {}
func (*InMemoryVfs) EnqueueListResult([]interfaces.VfsEntry, error)    {}
func (*InMemoryVfs) EnqueueCreateDirectoryResult(error)                {}
func (*InMemoryVfs) EnqueueDeleteResult(error)                         {}
func (*InMemoryVfs) Exists(context.Context, string) (bool, error)      { return false, nil }
func (*InMemoryVfs) ReadBytes(context.Context, string) ([]byte, error) { return nil, nil }
func (*InMemoryVfs) ReadText(context.Context, string) (string, error)  { return "", nil }
func (*InMemoryVfs) WriteBytes(context.Context, string, []byte, interfaces.WriteOptions) error {
	return nil
}

func (*InMemoryVfs) WriteText(context.Context, string, string, interfaces.WriteOptions) error {
	return nil
}

func (*InMemoryVfs) List(context.Context, string, interfaces.ListOptions) ([]interfaces.VfsEntry, error) {
	return nil, nil
}

func (*InMemoryVfs) CreateDirectory(context.Context, string, interfaces.DirectoryOptions) error {
	return nil
}

func (*InMemoryVfs) Delete(context.Context, string, interfaces.DirectoryOptions) error { return nil }

func (*InMemoryVfs) Files() map[string][]byte { return nil }

func (*InMemoryVfs) Directories() []string { return nil }

type InMemoryTerminal struct{}

func NewInMemoryTerminal() *InMemoryTerminal                             { return nil }
func (*InMemoryTerminal) EnqueueResult(interfaces.TerminalOutput, error) {}
func (*InMemoryTerminal) Run(context.Context, interfaces.TerminalCommand) (interfaces.TerminalOutput, error) {
	return interfaces.TerminalOutput{}, nil
}
func (*InMemoryTerminal) Commands() []interfaces.TerminalCommand { return nil }

type InMemoryLoggerSink struct{}

func NewInMemoryLoggerSink() *InMemoryLoggerSink            { return nil }
func (*InMemoryLoggerSink) EnqueueResult(error)             {}
func (*InMemoryLoggerSink) Emit(interfaces.LogRecord) error { return nil }
func (*InMemoryLoggerSink) Records() []interfaces.LogRecord { return nil }

type InMemoryMetricsCollector struct{}

func NewInMemoryMetricsCollector() *InMemoryMetricsCollector         { return nil }
func (*InMemoryMetricsCollector) EnqueueResult(error)                {}
func (*InMemoryMetricsCollector) Emit(interfaces.MetricRecord) error { return nil }
func (*InMemoryMetricsCollector) Records() []interfaces.MetricRecord { return nil }
