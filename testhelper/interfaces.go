// Package testhelper provides deterministic in-memory implementations of the
// interfaces package for consumer tests.
package testhelper

import (
	"context"
	"maps"
	"sync"
	"time"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	"github.com/AtomiCloud/diene.go-interfaces/testhelper/internal/faults"
	"github.com/AtomiCloud/diene.go-interfaces/testhelper/internal/vfsstore"
)

type scripted[T any] struct {
	value T
	err   error
}

// InMemorySystemOptions configures an InMemorySystem.
type InMemorySystemOptions struct {
	// Environment is the initial process environment.
	Environment map[string]string
	// Directory is the current working directory. The empty value is "/".
	Directory string
	// Now is the initial clock value. The zero value is the Unix epoch in UTC.
	Now time.Time
}

// InMemorySystem is a deterministic System with mutable in-memory process
// state and FIFO-scriptable results.
type InMemorySystem struct {
	state *inMemorySystemState
}

type inMemorySystemState struct {
	mu                 sync.Mutex
	environment        map[string]string
	directory          string
	now                time.Time
	requestedDelays    []time.Duration
	environmentResults []scripted[*string]
	directoryResults   []scripted[string]
	clockResults       []scripted[time.Time]
	delayResults       []error
}

// NewInMemorySystem creates a deterministic system from options.
func NewInMemorySystem(options InMemorySystemOptions) *InMemorySystem {
	directory := options.Directory
	if directory == "" {
		directory = "/"
	}
	now := options.Now
	if now.IsZero() {
		now = time.Unix(0, 0).UTC()
	}
	environment := make(map[string]string, len(options.Environment))
	maps.Copy(environment, options.Environment)
	return &InMemorySystem{state: &inMemorySystemState{environment: environment, directory: directory, now: now.UTC()}}
}

// EnqueueEnvironmentResult adds a FIFO Environment result.
func (s *InMemorySystem) EnqueueEnvironmentResult(value *string, err error) {
	s.state.mu.Lock()
	defer s.state.mu.Unlock()
	var copied *string
	if value != nil {
		owned := *value
		copied = &owned
	}
	s.state.environmentResults = append(s.state.environmentResults, scripted[*string]{value: copied, err: faults.Normalize(err)})
}

// EnqueueDirectoryResult adds a FIFO CurrentDirectory result.
func (s *InMemorySystem) EnqueueDirectoryResult(value string, err error) {
	s.state.mu.Lock()
	defer s.state.mu.Unlock()
	s.state.directoryResults = append(s.state.directoryResults, scripted[string]{value: value, err: faults.Normalize(err)})
}

// EnqueueClockResult adds a FIFO NowUTC result.
func (s *InMemorySystem) EnqueueClockResult(value time.Time, err error) {
	s.state.mu.Lock()
	defer s.state.mu.Unlock()
	s.state.clockResults = append(s.state.clockResults, scripted[time.Time]{value: value.UTC(), err: faults.Normalize(err)})
}

// EnqueueDelayResult adds a FIFO Delay result.
func (s *InMemorySystem) EnqueueDelayResult(err error) {
	s.state.mu.Lock()
	defer s.state.mu.Unlock()
	s.state.delayResults = append(s.state.delayResults, faults.Normalize(err))
}

// Environment implements interfaces.System.
func (s *InMemorySystem) Environment(name string) (*string, error) {
	s.state.mu.Lock()
	defer s.state.mu.Unlock()
	if len(s.state.environmentResults) > 0 {
		result := s.state.environmentResults[0]
		s.state.environmentResults = s.state.environmentResults[1:]
		if result.value == nil {
			return nil, result.err
		}
		copied := *result.value
		return &copied, result.err
	}
	value, ok := s.state.environment[name]
	if !ok {
		return nil, nil
	}
	return &value, nil
}

// CurrentDirectory implements interfaces.System.
func (s *InMemorySystem) CurrentDirectory() (string, error) {
	s.state.mu.Lock()
	defer s.state.mu.Unlock()
	if len(s.state.directoryResults) > 0 {
		result := s.state.directoryResults[0]
		s.state.directoryResults = s.state.directoryResults[1:]
		return result.value, result.err
	}
	return s.state.directory, nil
}

// NowUTC implements interfaces.System.
func (s *InMemorySystem) NowUTC() (time.Time, error) {
	s.state.mu.Lock()
	defer s.state.mu.Unlock()
	if len(s.state.clockResults) > 0 {
		result := s.state.clockResults[0]
		s.state.clockResults = s.state.clockResults[1:]
		return result.value.UTC(), result.err
	}
	return s.state.now.UTC(), nil
}

// Delay implements interfaces.System without sleeping.
func (s *InMemorySystem) Delay(_ context.Context, duration time.Duration) error {
	s.state.mu.Lock()
	defer s.state.mu.Unlock()
	s.state.requestedDelays = append(s.state.requestedDelays, duration)
	if len(s.state.delayResults) == 0 {
		return nil
	}
	err := s.state.delayResults[0]
	s.state.delayResults = s.state.delayResults[1:]
	return err
}

// RequestedDelays returns an independently owned snapshot of requested delays.
func (s *InMemorySystem) RequestedDelays() []time.Duration {
	s.state.mu.Lock()
	defer s.state.mu.Unlock()
	return append([]time.Duration(nil), s.state.requestedDelays...)
}

// SetEnvironment sets or replaces one in-memory environment variable.
func (s *InMemorySystem) SetEnvironment(name, value string) {
	s.state.mu.Lock()
	defer s.state.mu.Unlock()
	s.state.environment[name] = value
}

// SetDirectory replaces the in-memory working directory.
func (s *InMemorySystem) SetDirectory(directory string) {
	s.state.mu.Lock()
	defer s.state.mu.Unlock()
	s.state.directory = directory
}

// SetNow replaces the in-memory UTC clock.
func (s *InMemorySystem) SetNow(now time.Time) {
	s.state.mu.Lock()
	defer s.state.mu.Unlock()
	s.state.now = now.UTC()
}

// InMemoryVfsOptions configures an InMemoryVfs.
type InMemoryVfsOptions struct {
	// Files maps initial paths to their byte contents.
	Files map[string][]byte
	// Directories lists initial directories. Root is always present.
	Directories []string
}

// InMemoryVfs is a stateful byte-backed Vfs with FIFO-scriptable results. It is
// the synchronized, scriptable adapter around a vfsstore.Store that owns the
// storage algorithms.
type InMemoryVfs struct {
	state *inMemoryVfsState
}

type inMemoryVfsState struct {
	mu                     sync.Mutex
	store                  *vfsstore.Store
	existsResults          []scripted[bool]
	readBytesResults       []scripted[[]byte]
	readTextResults        []scripted[string]
	writeBytesResults      []error
	writeTextResults       []error
	listResults            []scripted[[]interfaces.VfsEntry]
	createDirectoryResults []error
	deleteResults          []error
}

// NewInMemoryVfs creates a byte-backed filesystem from options.
func NewInMemoryVfs(options InMemoryVfsOptions) *InMemoryVfs {
	store := vfsstore.New()
	store.Seed(options.Files, options.Directories)
	return &InMemoryVfs{state: &inMemoryVfsState{store: store}}
}

// EnqueueExistsResult adds a FIFO Exists result.
func (v *InMemoryVfs) EnqueueExistsResult(value bool, err error) {
	v.state.mu.Lock()
	defer v.state.mu.Unlock()
	v.state.existsResults = append(v.state.existsResults, scripted[bool]{value: value, err: faults.Normalize(err)})
}

// EnqueueReadBytesResult adds a FIFO ReadBytes result.
func (v *InMemoryVfs) EnqueueReadBytesResult(value []byte, err error) {
	v.state.mu.Lock()
	defer v.state.mu.Unlock()
	v.state.readBytesResults = append(v.state.readBytesResults, scripted[[]byte]{value: append([]byte(nil), value...), err: faults.Normalize(err)})
}

// EnqueueReadTextResult adds a FIFO ReadText result.
func (v *InMemoryVfs) EnqueueReadTextResult(value string, err error) {
	v.state.mu.Lock()
	defer v.state.mu.Unlock()
	v.state.readTextResults = append(v.state.readTextResults, scripted[string]{value: value, err: faults.Normalize(err)})
}

// EnqueueWriteBytesResult adds a FIFO WriteBytes result.
func (v *InMemoryVfs) EnqueueWriteBytesResult(err error) {
	v.state.mu.Lock()
	defer v.state.mu.Unlock()
	v.state.writeBytesResults = append(v.state.writeBytesResults, faults.Normalize(err))
}

// EnqueueWriteTextResult adds a FIFO WriteText result.
func (v *InMemoryVfs) EnqueueWriteTextResult(err error) {
	v.state.mu.Lock()
	defer v.state.mu.Unlock()
	v.state.writeTextResults = append(v.state.writeTextResults, faults.Normalize(err))
}

// EnqueueListResult adds a FIFO List result.
func (v *InMemoryVfs) EnqueueListResult(value []interfaces.VfsEntry, err error) {
	v.state.mu.Lock()
	defer v.state.mu.Unlock()
	copied := make([]interfaces.VfsEntry, len(value))
	for index, entry := range value {
		copied[index] = interfaces.NewVfsEntry(entry.Path, entry.Type, entry.Size, entry.ModifiedAt)
	}
	v.state.listResults = append(v.state.listResults, scripted[[]interfaces.VfsEntry]{value: copied, err: faults.Normalize(err)})
}

// EnqueueCreateDirectoryResult adds a FIFO CreateDirectory result.
func (v *InMemoryVfs) EnqueueCreateDirectoryResult(err error) {
	v.state.mu.Lock()
	defer v.state.mu.Unlock()
	v.state.createDirectoryResults = append(v.state.createDirectoryResults, faults.Normalize(err))
}

// EnqueueDeleteResult adds a FIFO Delete result.
func (v *InMemoryVfs) EnqueueDeleteResult(err error) {
	v.state.mu.Lock()
	defer v.state.mu.Unlock()
	v.state.deleteResults = append(v.state.deleteResults, faults.Normalize(err))
}

// Exists implements interfaces.Vfs.
func (v *InMemoryVfs) Exists(_ context.Context, path string) (bool, error) {
	v.state.mu.Lock()
	defer v.state.mu.Unlock()
	if len(v.state.existsResults) > 0 {
		result := v.state.existsResults[0]
		v.state.existsResults = v.state.existsResults[1:]
		return result.value, result.err
	}
	return v.state.store.Exists(path), nil
}

// ReadBytes implements interfaces.Vfs.
func (v *InMemoryVfs) ReadBytes(_ context.Context, path string) ([]byte, error) {
	v.state.mu.Lock()
	defer v.state.mu.Unlock()
	if len(v.state.readBytesResults) > 0 {
		result := v.state.readBytesResults[0]
		v.state.readBytesResults = v.state.readBytesResults[1:]
		return append([]byte(nil), result.value...), result.err
	}
	return v.state.store.ReadBytes(path)
}

// ReadText implements interfaces.Vfs.
func (v *InMemoryVfs) ReadText(_ context.Context, path string) (string, error) {
	v.state.mu.Lock()
	defer v.state.mu.Unlock()
	if len(v.state.readTextResults) > 0 {
		result := v.state.readTextResults[0]
		v.state.readTextResults = v.state.readTextResults[1:]
		return result.value, result.err
	}
	return v.state.store.ReadText(path)
}

// WriteBytes implements interfaces.Vfs.
func (v *InMemoryVfs) WriteBytes(_ context.Context, path string, bytes []byte, options interfaces.WriteOptions) error {
	v.state.mu.Lock()
	defer v.state.mu.Unlock()
	if len(v.state.writeBytesResults) > 0 {
		err := v.state.writeBytesResults[0]
		v.state.writeBytesResults = v.state.writeBytesResults[1:]
		return err
	}
	return v.state.store.Write(path, bytes, options)
}

// WriteText implements interfaces.Vfs.
func (v *InMemoryVfs) WriteText(_ context.Context, path, content string, options interfaces.WriteOptions) error {
	v.state.mu.Lock()
	defer v.state.mu.Unlock()
	if len(v.state.writeTextResults) > 0 {
		err := v.state.writeTextResults[0]
		v.state.writeTextResults = v.state.writeTextResults[1:]
		return err
	}
	return v.state.store.Write(path, []byte(content), options)
}

// List implements interfaces.Vfs.
func (v *InMemoryVfs) List(_ context.Context, path string, options interfaces.ListOptions) ([]interfaces.VfsEntry, error) {
	v.state.mu.Lock()
	defer v.state.mu.Unlock()
	if len(v.state.listResults) > 0 {
		result := v.state.listResults[0]
		v.state.listResults = v.state.listResults[1:]
		copied := make([]interfaces.VfsEntry, len(result.value))
		for index, entry := range result.value {
			copied[index] = interfaces.NewVfsEntry(entry.Path, entry.Type, entry.Size, entry.ModifiedAt)
		}
		return copied, result.err
	}
	return v.state.store.List(path, options)
}

// CreateDirectory implements interfaces.Vfs.
func (v *InMemoryVfs) CreateDirectory(_ context.Context, path string, options interfaces.DirectoryOptions) error {
	v.state.mu.Lock()
	defer v.state.mu.Unlock()
	if len(v.state.createDirectoryResults) > 0 {
		err := v.state.createDirectoryResults[0]
		v.state.createDirectoryResults = v.state.createDirectoryResults[1:]
		return err
	}
	return v.state.store.CreateDirectory(path, options)
}

// Delete implements interfaces.Vfs.
func (v *InMemoryVfs) Delete(_ context.Context, path string, options interfaces.DirectoryOptions) error {
	v.state.mu.Lock()
	defer v.state.mu.Unlock()
	if len(v.state.deleteResults) > 0 {
		err := v.state.deleteResults[0]
		v.state.deleteResults = v.state.deleteResults[1:]
		return err
	}
	return v.state.store.Delete(path, options)
}

// Files returns an independently owned snapshot of file contents.
func (v *InMemoryVfs) Files() map[string][]byte {
	v.state.mu.Lock()
	defer v.state.mu.Unlock()
	return v.state.store.Files()
}

// Directories returns a sorted, independently owned snapshot of directory paths.
func (v *InMemoryVfs) Directories() []string {
	v.state.mu.Lock()
	defer v.state.mu.Unlock()
	return v.state.store.Directories()
}

// InMemoryTerminal is a FIFO-scripted Terminal that records every command.
type InMemoryTerminal struct {
	state *inMemoryTerminalState
}

type inMemoryTerminalState struct {
	mu       sync.Mutex
	commands []interfaces.TerminalCommand
	results  []scripted[interfaces.TerminalOutput]
}

// NewInMemoryTerminal creates an empty terminal mock.
func NewInMemoryTerminal() *InMemoryTerminal {
	return &InMemoryTerminal{state: &inMemoryTerminalState{}}
}

// EnqueueResult adds a FIFO terminal result.
func (t *InMemoryTerminal) EnqueueResult(value interfaces.TerminalOutput, err error) {
	t.state.mu.Lock()
	defer t.state.mu.Unlock()
	t.state.results = append(t.state.results, scripted[interfaces.TerminalOutput]{value: value, err: faults.Normalize(err)})
}

// Run implements interfaces.Terminal.
func (t *InMemoryTerminal) Run(_ context.Context, command interfaces.TerminalCommand) (interfaces.TerminalOutput, error) {
	t.state.mu.Lock()
	defer t.state.mu.Unlock()
	t.state.commands = append(t.state.commands, command.Clone())
	if len(t.state.results) == 0 {
		return interfaces.TerminalOutput{}, faults.TerminalNotScripted(command.Executable)
	}
	result := t.state.results[0]
	t.state.results = t.state.results[1:]
	return result.value, result.err
}

// Commands returns an independently owned snapshot of requested commands.
func (t *InMemoryTerminal) Commands() []interfaces.TerminalCommand {
	t.state.mu.Lock()
	defer t.state.mu.Unlock()
	commands := make([]interfaces.TerminalCommand, len(t.state.commands))
	for index, command := range t.state.commands {
		commands[index] = command.Clone()
	}
	return commands
}

// InMemoryLoggerSink is a FIFO-scriptable LoggerSink that records successful emissions.
type InMemoryLoggerSink struct {
	state *inMemoryLoggerSinkState
}

type inMemoryLoggerSinkState struct {
	mu      sync.Mutex
	records []interfaces.LogRecord
	results []error
}

// NewInMemoryLoggerSink creates an empty logger mock.
func NewInMemoryLoggerSink() *InMemoryLoggerSink {
	return &InMemoryLoggerSink{state: &inMemoryLoggerSinkState{}}
}

// EnqueueResult adds a FIFO logger result.
func (s *InMemoryLoggerSink) EnqueueResult(err error) {
	s.state.mu.Lock()
	defer s.state.mu.Unlock()
	s.state.results = append(s.state.results, faults.Normalize(err))
}

// Emit implements interfaces.LoggerSink.
func (s *InMemoryLoggerSink) Emit(record interfaces.LogRecord) error {
	s.state.mu.Lock()
	defer s.state.mu.Unlock()
	if len(s.state.results) > 0 {
		err := s.state.results[0]
		s.state.results = s.state.results[1:]
		return err
	}
	s.state.records = append(s.state.records, record.Clone())
	return nil
}

// Records returns an independently owned snapshot of emitted records.
func (s *InMemoryLoggerSink) Records() []interfaces.LogRecord {
	s.state.mu.Lock()
	defer s.state.mu.Unlock()
	records := make([]interfaces.LogRecord, len(s.state.records))
	for index, record := range s.state.records {
		records[index] = record.Clone()
	}
	return records
}

// InMemoryMetricsCollector is a FIFO-scriptable MetricsCollector that records successful emissions.
type InMemoryMetricsCollector struct {
	state *inMemoryMetricsCollectorState
}

type inMemoryMetricsCollectorState struct {
	mu      sync.Mutex
	records []interfaces.MetricRecord
	results []error
}

// NewInMemoryMetricsCollector creates an empty metrics mock.
func NewInMemoryMetricsCollector() *InMemoryMetricsCollector {
	return &InMemoryMetricsCollector{state: &inMemoryMetricsCollectorState{}}
}

// EnqueueResult adds a FIFO metrics result.
func (s *InMemoryMetricsCollector) EnqueueResult(err error) {
	s.state.mu.Lock()
	defer s.state.mu.Unlock()
	s.state.results = append(s.state.results, faults.Normalize(err))
}

// Emit implements interfaces.MetricsCollector.
func (s *InMemoryMetricsCollector) Emit(record interfaces.MetricRecord) error {
	s.state.mu.Lock()
	defer s.state.mu.Unlock()
	if len(s.state.results) > 0 {
		err := s.state.results[0]
		s.state.results = s.state.results[1:]
		return err
	}
	s.state.records = append(s.state.records, record.Clone())
	return nil
}

// Records returns an independently owned snapshot of emitted records.
func (s *InMemoryMetricsCollector) Records() []interfaces.MetricRecord {
	s.state.mu.Lock()
	defer s.state.mu.Unlock()
	records := make([]interfaces.MetricRecord, len(s.state.records))
	for index, record := range s.state.records {
		records[index] = record.Clone()
	}
	return records
}

var (
	_ interfaces.System           = (*InMemorySystem)(nil)
	_ interfaces.Vfs              = (*InMemoryVfs)(nil)
	_ interfaces.Terminal         = (*InMemoryTerminal)(nil)
	_ interfaces.LoggerSink       = (*InMemoryLoggerSink)(nil)
	_ interfaces.MetricsCollector = (*InMemoryMetricsCollector)(nil)
)
