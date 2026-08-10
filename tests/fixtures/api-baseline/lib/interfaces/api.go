package interfaces

import (
	"context"
	"time"
)

type VfsEntryType string

const (
	VfsEntryTypeFile      VfsEntryType = "file"
	VfsEntryTypeDirectory VfsEntryType = "directory"
	VfsEntryTypeLink      VfsEntryType = "link"
)

func (t VfsEntryType) String() string { return string(t) }

type VfsEntry struct {
	Path       string
	Type       VfsEntryType
	Size       int64
	ModifiedAt *time.Time
}

func NewVfsEntry(string, VfsEntryType, int64, *time.Time) VfsEntry { return VfsEntry{} }

type (
	WriteOptions        struct{ CreateParents bool }
	VfsWriteOptions     = WriteOptions
	ListOptions         struct{ Recursive bool }
	VfsListOptions      = ListOptions
	DirectoryOptions    struct{ Recursive bool }
	VfsDirectoryOptions = DirectoryOptions
	Vfs                 interface {
		Exists(context.Context, string) (bool, error)
		ReadBytes(context.Context, string) ([]byte, error)
		ReadText(context.Context, string) (string, error)
		WriteBytes(context.Context, string, []byte, WriteOptions) error
		WriteText(context.Context, string, string, WriteOptions) error
		List(context.Context, string, ListOptions) ([]VfsEntry, error)
		CreateDirectory(context.Context, string, DirectoryOptions) error
		Delete(context.Context, string, DirectoryOptions) error
	}
)

type System interface {
	Environment(string) (*string, error)
	CurrentDirectory() (string, error)
	NowUTC() (time.Time, error)
	Delay(context.Context, time.Duration) error
}
type TerminalCommand struct {
	Executable               string
	Args                     []string
	WorkingDirectory         *string
	Environment              map[string]string
	IncludeParentEnvironment bool
	RunInShell               bool
}

func NewTerminalCommand(string, []string, *string, map[string]string, bool, bool) TerminalCommand {
	return TerminalCommand{}
}
func (TerminalCommand) Clone() TerminalCommand { return TerminalCommand{} }

type TerminalOutput struct {
	ExitCode int
	Stdout   string
	Stderr   string
}

func (TerminalOutput) Succeeded() bool { return false }

type Terminal interface {
	Run(context.Context, TerminalCommand) (TerminalOutput, error)
}
type LogLevel string

const (
	LogLevelTrace   LogLevel = "trace"
	LogLevelDebug   LogLevel = "debug"
	LogLevelInfo    LogLevel = "info"
	LogLevelWarning LogLevel = "warning"
	LogLevelError   LogLevel = "error"
	LogLevelFatal   LogLevel = "fatal"
)

func (l LogLevel) String() string { return string(l) }

type LogRecord struct {
	Timestamp  time.Time
	Level      LogLevel
	Message    string
	Attributes map[string]any
	Error      *string
	StackTrace *string
}

func NewLogRecord(time.Time, LogLevel, string, map[string]any, *string, *string) LogRecord {
	return LogRecord{}
}
func (LogRecord) Clone() LogRecord                  { return LogRecord{} }
func CloneAttributes(map[string]any) map[string]any { return nil }

type (
	LoggerSink interface{ Emit(LogRecord) error }
	MetricKind string
)

const (
	MetricKindCounter   MetricKind = "counter"
	MetricKindGauge     MetricKind = "gauge"
	MetricKindHistogram MetricKind = "histogram"
)

func (k MetricKind) String() string { return string(k) }

type MetricRecord struct {
	Timestamp  time.Time
	Name       string
	Kind       MetricKind
	Value      float64
	Unit       *string
	Attributes map[string]any
}

func NewMetricRecord(time.Time, string, MetricKind, float64, *string, map[string]any) MetricRecord {
	return MetricRecord{}
}
func (MetricRecord) Clone() MetricRecord { return MetricRecord{} }

type MetricsCollector interface{ Emit(MetricRecord) error }
