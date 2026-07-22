// Package testhelper provides deterministic in-memory implementations of the
// interfaces package for consumer tests.
package testhelper

import (
	"context"
	"maps"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
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
	return &InMemorySystem{environment: copyStringMap(options.Environment), directory: directory, now: now.UTC()}
}

// EnqueueEnvironmentResult adds a FIFO Environment result.
func (s *InMemorySystem) EnqueueEnvironmentResult(value *string, err error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.environmentResults = append(s.environmentResults, scripted[*string]{value: copyString(value), err: err})
}

// EnqueueDirectoryResult adds a FIFO CurrentDirectory result.
func (s *InMemorySystem) EnqueueDirectoryResult(value string, err error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.directoryResults = append(s.directoryResults, scripted[string]{value: value, err: err})
}

// EnqueueClockResult adds a FIFO NowUTC result.
func (s *InMemorySystem) EnqueueClockResult(value time.Time, err error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.clockResults = append(s.clockResults, scripted[time.Time]{value: value.UTC(), err: err})
}

// EnqueueDelayResult adds a FIFO Delay result.
func (s *InMemorySystem) EnqueueDelayResult(err error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.delayResults = append(s.delayResults, err)
}

// Environment implements interfaces.System.
func (s *InMemorySystem) Environment(name string) (*string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.environmentResults) > 0 {
		result := s.environmentResults[0]
		s.environmentResults = s.environmentResults[1:]
		return copyString(result.value), result.err
	}
	value, ok := s.environment[name]
	if !ok {
		return nil, nil
	}
	return &value, nil
}

// CurrentDirectory implements interfaces.System.
func (s *InMemorySystem) CurrentDirectory() (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.directoryResults) > 0 {
		result := s.directoryResults[0]
		s.directoryResults = s.directoryResults[1:]
		return result.value, result.err
	}
	return s.directory, nil
}

// NowUTC implements interfaces.System.
func (s *InMemorySystem) NowUTC() (time.Time, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.clockResults) > 0 {
		result := s.clockResults[0]
		s.clockResults = s.clockResults[1:]
		return result.value.UTC(), result.err
	}
	return s.now.UTC(), nil
}

// Delay implements interfaces.System without sleeping.
func (s *InMemorySystem) Delay(_ context.Context, duration time.Duration) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.requestedDelays = append(s.requestedDelays, duration)
	if len(s.delayResults) == 0 {
		return nil
	}
	err := s.delayResults[0]
	s.delayResults = s.delayResults[1:]
	return err
}

// RequestedDelays returns an independently owned snapshot of requested delays.
func (s *InMemorySystem) RequestedDelays() []time.Duration {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]time.Duration(nil), s.requestedDelays...)
}

// SetEnvironment sets or replaces one in-memory environment variable.
func (s *InMemorySystem) SetEnvironment(name, value string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.environment[name] = value
}

// SetDirectory replaces the in-memory working directory.
func (s *InMemorySystem) SetDirectory(directory string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.directory = directory
}

// SetNow replaces the in-memory UTC clock.
func (s *InMemorySystem) SetNow(now time.Time) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.now = now.UTC()
}

// InMemoryVfsOptions configures an InMemoryVfs.
type InMemoryVfsOptions struct {
	// Files maps initial paths to their byte contents.
	Files map[string][]byte
	// Directories lists initial directories. Root is always present.
	Directories []string
}

// InMemoryVfs is a stateful byte-backed Vfs with FIFO-scriptable results.
type InMemoryVfs struct {
	mu                     sync.Mutex
	files                  map[string][]byte
	directories            map[string]struct{}
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
	vfs := &InMemoryVfs{files: map[string][]byte{}, directories: map[string]struct{}{"/": {}}}
	for path, bytes := range options.Files {
		vfs.files[normalize(path)] = append([]byte(nil), bytes...)
	}
	for _, directory := range options.Directories {
		vfs.directories[normalize(directory)] = struct{}{}
	}
	return vfs
}

// EnqueueExistsResult adds a FIFO Exists result.
func (v *InMemoryVfs) EnqueueExistsResult(value bool, err error) {
	v.mu.Lock()
	defer v.mu.Unlock()
	v.existsResults = append(v.existsResults, scripted[bool]{value: value, err: err})
}

// EnqueueReadBytesResult adds a FIFO ReadBytes result.
func (v *InMemoryVfs) EnqueueReadBytesResult(value []byte, err error) {
	v.mu.Lock()
	defer v.mu.Unlock()
	v.readBytesResults = append(v.readBytesResults, scripted[[]byte]{value: append([]byte(nil), value...), err: err})
}

// EnqueueReadTextResult adds a FIFO ReadText result.
func (v *InMemoryVfs) EnqueueReadTextResult(value string, err error) {
	v.mu.Lock()
	defer v.mu.Unlock()
	v.readTextResults = append(v.readTextResults, scripted[string]{value: value, err: err})
}

// EnqueueWriteBytesResult adds a FIFO WriteBytes result.
func (v *InMemoryVfs) EnqueueWriteBytesResult(err error) {
	v.mu.Lock()
	defer v.mu.Unlock()
	v.writeBytesResults = append(v.writeBytesResults, err)
}

// EnqueueWriteTextResult adds a FIFO WriteText result.
func (v *InMemoryVfs) EnqueueWriteTextResult(err error) {
	v.mu.Lock()
	defer v.mu.Unlock()
	v.writeTextResults = append(v.writeTextResults, err)
}

// EnqueueListResult adds a FIFO List result.
func (v *InMemoryVfs) EnqueueListResult(value []interfaces.VfsEntry, err error) {
	v.mu.Lock()
	defer v.mu.Unlock()
	v.listResults = append(v.listResults, scripted[[]interfaces.VfsEntry]{value: cloneEntries(value), err: err})
}

// EnqueueCreateDirectoryResult adds a FIFO CreateDirectory result.
func (v *InMemoryVfs) EnqueueCreateDirectoryResult(err error) {
	v.mu.Lock()
	defer v.mu.Unlock()
	v.createDirectoryResults = append(v.createDirectoryResults, err)
}

// EnqueueDeleteResult adds a FIFO Delete result.
func (v *InMemoryVfs) EnqueueDeleteResult(err error) {
	v.mu.Lock()
	defer v.mu.Unlock()
	v.deleteResults = append(v.deleteResults, err)
}

// Exists implements interfaces.Vfs.
func (v *InMemoryVfs) Exists(_ context.Context, path string) (bool, error) {
	v.mu.Lock()
	defer v.mu.Unlock()
	if len(v.existsResults) > 0 {
		result := v.existsResults[0]
		v.existsResults = v.existsResults[1:]
		return result.value, result.err
	}
	normalized := normalize(path)
	_, file := v.files[normalized]
	_, directory := v.directories[normalized]
	return file || directory, nil
}

// ReadBytes implements interfaces.Vfs.
func (v *InMemoryVfs) ReadBytes(_ context.Context, path string) ([]byte, error) {
	v.mu.Lock()
	defer v.mu.Unlock()
	if len(v.readBytesResults) > 0 {
		result := v.readBytesResults[0]
		v.readBytesResults = v.readBytesResults[1:]
		return append([]byte(nil), result.value...), result.err
	}
	normalized := normalize(path)
	bytes, ok := v.files[normalized]
	if !ok {
		return nil, pathNotFound(normalized)
	}
	return append([]byte(nil), bytes...), nil
}

// ReadText implements interfaces.Vfs.
func (v *InMemoryVfs) ReadText(_ context.Context, path string) (string, error) {
	v.mu.Lock()
	defer v.mu.Unlock()
	if len(v.readTextResults) > 0 {
		result := v.readTextResults[0]
		v.readTextResults = v.readTextResults[1:]
		return result.value, result.err
	}
	normalized := normalize(path)
	bytes, ok := v.files[normalized]
	if !ok {
		return "", pathNotFound(normalized)
	}
	return string(bytes), nil
}

// WriteBytes implements interfaces.Vfs.
func (v *InMemoryVfs) WriteBytes(_ context.Context, path string, bytes []byte, options interfaces.WriteOptions) error {
	v.mu.Lock()
	defer v.mu.Unlock()
	if len(v.writeBytesResults) > 0 {
		err := v.writeBytesResults[0]
		v.writeBytesResults = v.writeBytesResults[1:]
		return err
	}
	return v.write(path, bytes, options)
}

// WriteText implements interfaces.Vfs.
func (v *InMemoryVfs) WriteText(_ context.Context, path, content string, options interfaces.WriteOptions) error {
	v.mu.Lock()
	defer v.mu.Unlock()
	if len(v.writeTextResults) > 0 {
		err := v.writeTextResults[0]
		v.writeTextResults = v.writeTextResults[1:]
		return err
	}
	return v.write(path, []byte(content), options)
}

// List implements interfaces.Vfs.
func (v *InMemoryVfs) List(_ context.Context, path string, options interfaces.ListOptions) ([]interfaces.VfsEntry, error) {
	v.mu.Lock()
	defer v.mu.Unlock()
	if len(v.listResults) > 0 {
		result := v.listResults[0]
		v.listResults = v.listResults[1:]
		return cloneEntries(result.value), result.err
	}
	normalized := normalize(path)
	if _, ok := v.directories[normalized]; !ok {
		return nil, pathNotFound(normalized)
	}
	prefix := normalized
	if prefix != "/" {
		prefix += "/"
	}
	entries := make([]interfaces.VfsEntry, 0)
	for directory := range v.directories {
		if directory != normalized && strings.HasPrefix(directory, prefix) && (options.Recursive || !strings.Contains(strings.TrimPrefix(directory, prefix), "/")) {
			entries = append(entries, interfaces.NewVfsEntry(directory, interfaces.VfsEntryTypeDirectory, 0, nil))
		}
	}
	for file, bytes := range v.files {
		if strings.HasPrefix(file, prefix) && (options.Recursive || !strings.Contains(strings.TrimPrefix(file, prefix), "/")) {
			entries = append(entries, interfaces.NewVfsEntry(file, interfaces.VfsEntryTypeFile, int64(len(bytes)), nil))
		}
	}
	slices.SortFunc(entries, func(left, right interfaces.VfsEntry) int { return strings.Compare(left.Path, right.Path) })
	return entries, nil
}

// CreateDirectory implements interfaces.Vfs.
func (v *InMemoryVfs) CreateDirectory(_ context.Context, path string, options interfaces.DirectoryOptions) error {
	v.mu.Lock()
	defer v.mu.Unlock()
	if len(v.createDirectoryResults) > 0 {
		err := v.createDirectoryResults[0]
		v.createDirectoryResults = v.createDirectoryResults[1:]
		return err
	}
	normalized := normalize(path)
	parent := parent(normalized)
	if _, ok := v.directories[parent]; !ok && !options.Recursive {
		return pathNotFound(parent)
	}
	if options.Recursive {
		v.createParents(normalized)
	} else {
		v.directories[normalized] = struct{}{}
	}
	return nil
}

// Delete implements interfaces.Vfs.
func (v *InMemoryVfs) Delete(_ context.Context, path string, options interfaces.DirectoryOptions) error {
	v.mu.Lock()
	defer v.mu.Unlock()
	if len(v.deleteResults) > 0 {
		err := v.deleteResults[0]
		v.deleteResults = v.deleteResults[1:]
		return err
	}
	normalized := normalize(path)
	if _, ok := v.files[normalized]; ok {
		delete(v.files, normalized)
		return nil
	}
	if _, ok := v.directories[normalized]; !ok {
		return pathNotFound(normalized)
	}
	prefix := normalized
	if prefix != "/" {
		prefix += "/"
	}
	for file := range v.files {
		if strings.HasPrefix(file, prefix) && !options.Recursive {
			return directoryNotEmpty(normalized)
		}
	}
	for directory := range v.directories {
		if directory != normalized && strings.HasPrefix(directory, prefix) && !options.Recursive {
			return directoryNotEmpty(normalized)
		}
	}
	for file := range v.files {
		if strings.HasPrefix(file, prefix) {
			delete(v.files, file)
		}
	}
	for directory := range v.directories {
		if directory == normalized || strings.HasPrefix(directory, prefix) {
			delete(v.directories, directory)
		}
	}
	v.directories["/"] = struct{}{}
	return nil
}

// Files returns an independently owned snapshot of file contents.
func (v *InMemoryVfs) Files() map[string][]byte {
	v.mu.Lock()
	defer v.mu.Unlock()
	copied := make(map[string][]byte, len(v.files))
	for path, bytes := range v.files {
		copied[path] = append([]byte(nil), bytes...)
	}
	return copied
}

// Directories returns a sorted, independently owned snapshot of directory paths.
func (v *InMemoryVfs) Directories() []string {
	v.mu.Lock()
	defer v.mu.Unlock()
	directories := make([]string, 0, len(v.directories))
	for directory := range v.directories {
		directories = append(directories, directory)
	}
	slices.Sort(directories)
	return directories
}

func (v *InMemoryVfs) write(path string, bytes []byte, options interfaces.WriteOptions) error {
	normalized := normalize(path)
	parentPath := parent(normalized)
	if _, ok := v.directories[parentPath]; !ok {
		if !options.CreateParents {
			return pathNotFound(parentPath)
		}
		v.createParents(parentPath)
	}
	v.files[normalized] = append([]byte(nil), bytes...)
	return nil
}

func (v *InMemoryVfs) createParents(path string) {
	var current strings.Builder
	for segment := range strings.SplitSeq(path, "/") {
		if segment != "" {
			current.WriteByte('/')
			current.WriteString(segment)
			v.directories[current.String()] = struct{}{}
		}
	}
	v.directories["/"] = struct{}{}
}

// InMemoryTerminal is a FIFO-scripted Terminal that records every command.
type InMemoryTerminal struct {
	mu       sync.Mutex
	commands []interfaces.TerminalCommand
	results  []scripted[interfaces.TerminalOutput]
}

// NewInMemoryTerminal creates an empty terminal mock.
func NewInMemoryTerminal() *InMemoryTerminal { return &InMemoryTerminal{} }

// EnqueueResult adds a FIFO terminal result.
func (t *InMemoryTerminal) EnqueueResult(value interfaces.TerminalOutput, err error) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.results = append(t.results, scripted[interfaces.TerminalOutput]{value: value, err: err})
}

// Run implements interfaces.Terminal.
func (t *InMemoryTerminal) Run(_ context.Context, command interfaces.TerminalCommand) (interfaces.TerminalOutput, error) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.commands = append(t.commands, command.Clone())
	if len(t.results) == 0 {
		return interfaces.TerminalOutput{}, terminalNotScripted(command.Executable)
	}
	result := t.results[0]
	t.results = t.results[1:]
	return result.value, result.err
}

// Commands returns an independently owned snapshot of requested commands.
func (t *InMemoryTerminal) Commands() []interfaces.TerminalCommand {
	t.mu.Lock()
	defer t.mu.Unlock()
	commands := make([]interfaces.TerminalCommand, len(t.commands))
	for index, command := range t.commands {
		commands[index] = command.Clone()
	}
	return commands
}

// InMemoryLoggerSink is a FIFO-scriptable LoggerSink that records successful emissions.
type InMemoryLoggerSink struct {
	mu      sync.Mutex
	records []interfaces.LogRecord
	results []error
}

// NewInMemoryLoggerSink creates an empty logger mock.
func NewInMemoryLoggerSink() *InMemoryLoggerSink { return &InMemoryLoggerSink{} }

// EnqueueResult adds a FIFO logger result.
func (s *InMemoryLoggerSink) EnqueueResult(err error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.results = append(s.results, err)
}

// Emit implements interfaces.LoggerSink.
func (s *InMemoryLoggerSink) Emit(record interfaces.LogRecord) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.results) > 0 {
		err := s.results[0]
		s.results = s.results[1:]
		return err
	}
	s.records = append(s.records, record.Clone())
	return nil
}

// Records returns an independently owned snapshot of emitted records.
func (s *InMemoryLoggerSink) Records() []interfaces.LogRecord {
	s.mu.Lock()
	defer s.mu.Unlock()
	records := make([]interfaces.LogRecord, len(s.records))
	for index, record := range s.records {
		records[index] = record.Clone()
	}
	return records
}

// InMemoryMetricsCollector is a FIFO-scriptable MetricsCollector that records successful emissions.
type InMemoryMetricsCollector struct {
	mu      sync.Mutex
	records []interfaces.MetricRecord
	results []error
}

// NewInMemoryMetricsCollector creates an empty metrics mock.
func NewInMemoryMetricsCollector() *InMemoryMetricsCollector { return &InMemoryMetricsCollector{} }

// EnqueueResult adds a FIFO metrics result.
func (s *InMemoryMetricsCollector) EnqueueResult(err error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.results = append(s.results, err)
}

// Emit implements interfaces.MetricsCollector.
func (s *InMemoryMetricsCollector) Emit(record interfaces.MetricRecord) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.results) > 0 {
		err := s.results[0]
		s.results = s.results[1:]
		return err
	}
	s.records = append(s.records, record.Clone())
	return nil
}

// Records returns an independently owned snapshot of emitted records.
func (s *InMemoryMetricsCollector) Records() []interfaces.MetricRecord {
	s.mu.Lock()
	defer s.mu.Unlock()
	records := make([]interfaces.MetricRecord, len(s.records))
	for index, record := range s.records {
		records[index] = record.Clone()
	}
	return records
}

func copyString(value *string) *string {
	if value == nil {
		return nil
	}
	copied := *value
	return &copied
}

func copyStringMap(values map[string]string) map[string]string {
	copied := make(map[string]string, len(values))
	maps.Copy(copied, values)
	return copied
}

func cloneEntries(entries []interfaces.VfsEntry) []interfaces.VfsEntry {
	copied := make([]interfaces.VfsEntry, len(entries))
	for index, entry := range entries {
		copied[index] = interfaces.NewVfsEntry(entry.Path, entry.Type, entry.Size, entry.ModifiedAt)
	}
	return copied
}

func normalize(path string) string {
	segments := make([]string, 0)
	for segment := range strings.SplitSeq(path, "/") {
		if segment != "" {
			segments = append(segments, segment)
		}
	}
	return "/" + strings.Join(segments, "/")
}

func parent(path string) string {
	if path == "/" {
		return "/"
	}
	index := strings.LastIndex(path, "/")
	if index == 0 {
		return "/"
	}
	return path[:index]
}

func pathNotFound(path string) error {
	return interfacesProblem("path-not-found", "Path not found", path, 404)
}

func directoryNotEmpty(path string) error {
	return interfacesProblem("directory-not-empty", "Directory not empty", path, 409)
}

func terminalNotScripted(executable string) error {
	return interfacesProblem("terminal-result-not-scripted", "Terminal result not scripted", executable, 500)
}

func interfacesProblem(id, title, detail string, status int) error {
	return problem.NewError(problem.Problem{Type: "https://diene.atomicloud.com/problems/interfaces/1/" + id, Title: title, Status: status, Detail: &detail, Data: map[string]any{"id": id}})
}

var (
	_ interfaces.System           = (*InMemorySystem)(nil)
	_ interfaces.Vfs              = (*InMemoryVfs)(nil)
	_ interfaces.Terminal         = (*InMemoryTerminal)(nil)
	_ interfaces.LoggerSink       = (*InMemoryLoggerSink)(nil)
	_ interfaces.MetricsCollector = (*InMemoryMetricsCollector)(nil)
)
