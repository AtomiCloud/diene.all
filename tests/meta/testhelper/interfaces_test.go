package testhelper_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	probtest "github.com/AtomiCloud/diene.go-errors-problems/testhelper"
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	"github.com/AtomiCloud/diene.go-interfaces/testhelper"
)

// canonicalTypePrefix is the fixed testhelper fault type-URI prefix. Every
// intrinsic fault resolves its type through problem.TypeURI from the fixed
// portal, so the id is the final canonical path segment.
const canonicalTypePrefix = "https://docs.diene.atomicloud.com/docs/diene/go/interfaces/testhelper/v1/"

func TestInMemorySystem(t *testing.T) {
	value := "value"
	system := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{Environment: map[string]string{"present": value}, Directory: "/work", Now: time.Date(2026, 7, 22, 2, 3, 4, 0, time.FixedZone("offset", 3600))})
	got, err := system.Environment("present")
	if err != nil || got == nil || *got != value {
		t.Fatalf("environment: %v %v", got, err)
	}
	if got, err = system.Environment("missing"); err != nil || got != nil {
		t.Fatalf("missing environment: %v %v", got, err)
	}
	system.SetEnvironment("new", "yes")
	got, _ = system.Environment("new")
	if *got != "yes" {
		t.Fatal("set environment failed")
	}
	queued := "queued"
	injected := errors.New("injected")
	system.EnqueueEnvironmentResult(&queued, injected)
	queued = "mutated"
	got, err = system.Environment("x")
	if !errors.Is(err, injected) || *got != "queued" {
		t.Fatalf("queued environment: %v %v", got, err)
	}
	system.EnqueueEnvironmentResult(nil, nil)
	got, err = system.Environment("x")
	if err != nil || got != nil {
		t.Fatal("nil queued environment failed")
	}
	if directory, currentErr := system.CurrentDirectory(); currentErr != nil || directory != "/work" {
		t.Fatalf("directory: %q %v", directory, currentErr)
	}
	system.SetDirectory("/other")
	system.EnqueueDirectoryResult("/queued", injected)
	directory, err := system.CurrentDirectory()
	if directory != "/queued" || !errors.Is(err, injected) {
		t.Fatal("queued directory failed")
	}
	directory, _ = system.CurrentDirectory()
	if directory != "/other" {
		t.Fatal("set directory failed")
	}
	now, err := system.NowUTC()
	if err != nil || now.Location() != time.UTC {
		t.Fatalf("clock: %v %v", now, err)
	}
	system.SetNow(time.Time{})
	system.EnqueueClockResult(time.Date(2026, 1, 1, 0, 0, 0, 0, time.FixedZone("offset", 3600)), injected)
	now, err = system.NowUTC()
	if !errors.Is(err, injected) || now.Location() != time.UTC {
		t.Fatal("queued clock failed")
	}
	now, _ = system.NowUTC()
	if !now.IsZero() {
		t.Fatal("set clock failed")
	}
	system.EnqueueDelayResult(injected)
	if err := system.Delay(context.Background(), time.Second); !errors.Is(err, injected) {
		t.Fatal("queued delay failed")
	}
	if err := system.Delay(context.Background(), 2*time.Second); err != nil {
		t.Fatal(err)
	}
	delays := system.RequestedDelays()
	delays[0] = 0
	if system.RequestedDelays()[0] != time.Second {
		t.Fatal("delays not copied")
	}
	defaults := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})
	if directory, _ := defaults.CurrentDirectory(); directory != "/" {
		t.Fatal("default directory")
	}
	now, _ = defaults.NowUTC()
	if !now.Equal(time.Unix(0, 0).UTC()) {
		t.Fatal("default clock")
	}
}

func TestInMemoryVfs(t *testing.T) {
	vfs := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{Files: map[string][]byte{"//a//file": []byte("text")}, Directories: []string{"/a", "/a/sub"}})
	if exists, err := vfs.Exists(context.Background(), "/a/file"); err != nil || !exists {
		t.Fatal("expected existing file")
	}
	if exists, err := vfs.Exists(context.Background(), "/no"); err != nil || exists {
		t.Fatal("expected absent file")
	}
	injected := errors.New("injected")
	vfs.EnqueueExistsResult(true, injected)
	if exists, err := vfs.Exists(context.Background(), "/no"); !exists || !errors.Is(err, injected) {
		t.Fatal("scripted exists")
	}
	bytes, err := vfs.ReadBytes(context.Background(), "/a/file")
	if err != nil || string(bytes) != "text" {
		t.Fatal("read bytes")
	}
	bytes[0] = 'x'
	bytes, _ = vfs.ReadBytes(context.Background(), "/a/file")
	if string(bytes) != "text" {
		t.Fatal("read bytes aliases state")
	}
	assertProblem(t, mustErr(vfs.ReadBytes(context.Background(), "/missing")), "path-not-found", 404)
	vfs.EnqueueReadBytesResult([]byte("queued"), injected)
	bytes, err = vfs.ReadBytes(context.Background(), "/x")
	if !errors.Is(err, injected) || string(bytes) != "queued" {
		t.Fatal("scripted bytes")
	}
	text, err := vfs.ReadText(context.Background(), "/a/file")
	if err != nil || text != "text" {
		t.Fatal("read text")
	}
	assertProblem(t, mustErr(vfs.ReadText(context.Background(), "/missing")), "path-not-found", 404)
	vfs.EnqueueReadTextResult("queued", injected)
	text, err = vfs.ReadText(context.Background(), "/x")
	if !errors.Is(err, injected) || text != "queued" {
		t.Fatal("scripted text")
	}
	assertProblem(t, vfs.WriteBytes(context.Background(), "/missing/file", []byte("x"), interfaces.WriteOptions{}), "path-not-found", 404)
	if writeErr := vfs.WriteBytes(context.Background(), "/new/file", []byte("bytes"), interfaces.WriteOptions{CreateParents: true}); writeErr != nil {
		t.Fatal(writeErr)
	}
	vfs.EnqueueWriteBytesResult(injected)
	if writeErr := vfs.WriteBytes(context.Background(), "/x", nil, interfaces.WriteOptions{}); !errors.Is(writeErr, injected) {
		t.Fatal("scripted write bytes")
	}
	if writeErr := vfs.WriteText(context.Background(), "/new/text", "hello", interfaces.WriteOptions{}); writeErr != nil {
		t.Fatal(writeErr)
	}
	vfs.EnqueueWriteTextResult(injected)
	if writeErr := vfs.WriteText(context.Background(), "/x", "x", interfaces.WriteOptions{}); !errors.Is(writeErr, injected) {
		t.Fatal("scripted write text")
	}
	entries, err := vfs.List(context.Background(), "/a", interfaces.ListOptions{})
	if err != nil || len(entries) != 2 || entries[0].Path != "/a/file" || entries[1].Path != "/a/sub" {
		t.Fatalf("list direct: %#v %v", entries, err)
	}
	entries, err = vfs.List(context.Background(), "/", interfaces.ListOptions{Recursive: true})
	if err != nil || len(entries) < 4 {
		t.Fatalf("list recursive: %#v %v", entries, err)
	}
	assertProblem(t, mustErr(vfs.List(context.Background(), "/missing", interfaces.ListOptions{})), "path-not-found", 404)
	vfs.EnqueueListResult([]interfaces.VfsEntry{{Path: "/script", Type: interfaces.VfsEntryTypeLink}}, injected)
	entries, err = vfs.List(context.Background(), "/", interfaces.ListOptions{})
	if !errors.Is(err, injected) || len(entries) != 1 {
		t.Fatal("scripted list")
	}
	entries[0].Path = "changed"
	entries, _ = vfs.List(context.Background(), "/", interfaces.ListOptions{})
	if len(entries) == 0 || entries[0].Path == "changed" {
		t.Fatal("list not copied")
	}
	assertProblem(t, vfs.CreateDirectory(context.Background(), "/none/child", interfaces.DirectoryOptions{}), "path-not-found", 404)
	if err := vfs.CreateDirectory(context.Background(), "/created/a", interfaces.DirectoryOptions{Recursive: true}); err != nil {
		t.Fatal(err)
	}
	if err := vfs.WriteText(context.Background(), "/created/a/file", "recursive", interfaces.WriteOptions{}); err != nil {
		t.Fatal(err)
	}
	if err := vfs.CreateDirectory(context.Background(), "/created/b", interfaces.DirectoryOptions{}); err != nil {
		t.Fatal(err)
	}
	if err := vfs.CreateDirectory(context.Background(), "/top", interfaces.DirectoryOptions{}); err != nil {
		t.Fatal(err)
	}
	if err := vfs.CreateDirectory(context.Background(), "/", interfaces.DirectoryOptions{}); err != nil {
		t.Fatal(err)
	}
	vfs.EnqueueCreateDirectoryResult(injected)
	if err := vfs.CreateDirectory(context.Background(), "/x", interfaces.DirectoryOptions{}); !errors.Is(err, injected) {
		t.Fatal("scripted mkdir")
	}
	assertProblem(t, vfs.Delete(context.Background(), "/missing", interfaces.DirectoryOptions{}), "path-not-found", 404)
	assertProblem(t, vfs.Delete(context.Background(), "/a", interfaces.DirectoryOptions{}), "directory-not-empty", 409)
	if err := vfs.Delete(context.Background(), "/a/file", interfaces.DirectoryOptions{}); err != nil {
		t.Fatal(err)
	}
	if err := vfs.Delete(context.Background(), "/a", interfaces.DirectoryOptions{Recursive: true}); err != nil {
		t.Fatal(err)
	}
	if err := vfs.Delete(context.Background(), "/created", interfaces.DirectoryOptions{Recursive: true}); err != nil {
		t.Fatal(err)
	}
	vfs.EnqueueDeleteResult(injected)
	if err := vfs.Delete(context.Background(), "/x", interfaces.DirectoryOptions{}); !errors.Is(err, injected) {
		t.Fatal("scripted delete")
	}
	files := vfs.Files()
	for _, bytes := range files {
		if len(bytes) > 0 {
			bytes[0] = 'x'
		}
	}
	for _, bytes := range vfs.Files() {
		if string(bytes) == "x" {
			t.Fatal("files not copied")
		}
	}
	directories := vfs.Directories()
	directories[0] = "changed"
	if vfs.Directories()[0] != "/" {
		t.Fatal("directories not copied")
	}
	root := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{Files: map[string][]byte{"/child/file": []byte("x")}, Directories: []string{"/child"}})
	if err := root.Delete(context.Background(), "/", interfaces.DirectoryOptions{Recursive: true}); err != nil {
		t.Fatal(err)
	}
	directoriesOnly := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{Directories: []string{"/parent", "/parent/child"}})
	assertProblem(t, directoriesOnly.Delete(context.Background(), "/parent", interfaces.DirectoryOptions{}), "directory-not-empty", 409)
}

func TestInMemoryTerminalLoggerAndMetrics(t *testing.T) {
	injected := errors.New("injected")
	terminal := testhelper.NewInMemoryTerminal()
	command := interfaces.NewTerminalCommand("tool", []string{"one"}, nil, map[string]string{"A": "1"}, true, false)
	_, err := terminal.Run(context.Background(), command)
	assertProblem(t, err, "terminal-result-not-scripted", 500)
	terminal.EnqueueResult(interfaces.TerminalOutput{ExitCode: 2, Stderr: "no"}, injected)
	output, err := terminal.Run(context.Background(), command)
	if !errors.Is(err, injected) || output.ExitCode != 2 {
		t.Fatal("scripted terminal")
	}
	commands := terminal.Commands()
	commands[0].Args[0] = "changed"
	if terminal.Commands()[0].Args[0] != "one" {
		t.Fatal("commands not copied")
	}
	logger := testhelper.NewInMemoryLoggerSink()
	log := interfaces.NewLogRecord(time.Now(), interfaces.LogLevelInfo, "message", map[string]any{"key": "value"}, nil, nil)
	logger.EnqueueResult(injected)
	if err := logger.Emit(log); !errors.Is(err, injected) {
		t.Fatal("scripted logger")
	}
	if len(logger.Records()) != 0 {
		t.Fatal("failed log must not record")
	}
	if err := logger.Emit(log); err != nil {
		t.Fatal(err)
	}
	logs := logger.Records()
	logs[0].Attributes["key"] = "changed"
	if logger.Records()[0].Attributes["key"] != "value" {
		t.Fatal("logs not copied")
	}
	metrics := testhelper.NewInMemoryMetricsCollector()
	metric := interfaces.NewMetricRecord(time.Now(), "count", interfaces.MetricKindCounter, 1, nil, map[string]any{"key": "value"})
	metrics.EnqueueResult(injected)
	if err := metrics.Emit(metric); !errors.Is(err, injected) {
		t.Fatal("scripted metrics")
	}
	if len(metrics.Records()) != 0 {
		t.Fatal("failed metric must not record")
	}
	if err := metrics.Emit(metric); err != nil {
		t.Fatal(err)
	}
	records := metrics.Records()
	records[0].Attributes["key"] = "changed"
	if metrics.Records()[0].Attributes["key"] != "value" {
		t.Fatal("metrics not copied")
	}
}

// TestInjectedErrorsAreProblemTyped proves every seam of every mock normalizes
// an injected plain error so it is recoverable as *problem.Error while
// errors.Is still reaches the original cause.
func TestInjectedErrorsAreProblemTyped(t *testing.T) {
	ctx := context.Background()
	seams := map[string]func(injected error) error{
		"system.environment": func(injected error) error {
			s := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})
			s.EnqueueEnvironmentResult(nil, injected)
			_, err := s.Environment("x")
			return err
		},
		"system.directory": func(injected error) error {
			s := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})
			s.EnqueueDirectoryResult("", injected)
			_, err := s.CurrentDirectory()
			return err
		},
		"system.clock": func(injected error) error {
			s := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})
			s.EnqueueClockResult(time.Time{}, injected)
			_, err := s.NowUTC()
			return err
		},
		"system.delay": func(injected error) error {
			s := testhelper.NewInMemorySystem(testhelper.InMemorySystemOptions{})
			s.EnqueueDelayResult(injected)
			return s.Delay(ctx, time.Second)
		},
		"vfs.exists": func(injected error) error {
			v := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})
			v.EnqueueExistsResult(false, injected)
			_, err := v.Exists(ctx, "/x")
			return err
		},
		"vfs.readBytes": func(injected error) error {
			v := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})
			v.EnqueueReadBytesResult(nil, injected)
			_, err := v.ReadBytes(ctx, "/x")
			return err
		},
		"vfs.readText": func(injected error) error {
			v := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})
			v.EnqueueReadTextResult("", injected)
			_, err := v.ReadText(ctx, "/x")
			return err
		},
		"vfs.writeBytes": func(injected error) error {
			v := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})
			v.EnqueueWriteBytesResult(injected)
			return v.WriteBytes(ctx, "/x", nil, interfaces.WriteOptions{})
		},
		"vfs.writeText": func(injected error) error {
			v := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})
			v.EnqueueWriteTextResult(injected)
			return v.WriteText(ctx, "/x", "", interfaces.WriteOptions{})
		},
		"vfs.list": func(injected error) error {
			v := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})
			v.EnqueueListResult(nil, injected)
			_, err := v.List(ctx, "/", interfaces.ListOptions{})
			return err
		},
		"vfs.createDirectory": func(injected error) error {
			v := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})
			v.EnqueueCreateDirectoryResult(injected)
			return v.CreateDirectory(ctx, "/x", interfaces.DirectoryOptions{})
		},
		"vfs.delete": func(injected error) error {
			v := testhelper.NewInMemoryVfs(testhelper.InMemoryVfsOptions{})
			v.EnqueueDeleteResult(injected)
			return v.Delete(ctx, "/x", interfaces.DirectoryOptions{})
		},
		"terminal.run": func(injected error) error {
			term := testhelper.NewInMemoryTerminal()
			term.EnqueueResult(interfaces.TerminalOutput{}, injected)
			_, err := term.Run(ctx, interfaces.NewTerminalCommand("tool", nil, nil, nil, false, false))
			return err
		},
		"logger.emit": func(injected error) error {
			logger := testhelper.NewInMemoryLoggerSink()
			logger.EnqueueResult(injected)
			return logger.Emit(interfaces.NewLogRecord(time.Now(), interfaces.LogLevelInfo, "m", nil, nil, nil))
		},
		"metrics.emit": func(injected error) error {
			metrics := testhelper.NewInMemoryMetricsCollector()
			metrics.EnqueueResult(injected)
			return metrics.Emit(interfaces.NewMetricRecord(time.Now(), "c", interfaces.MetricKindCounter, 1, nil, nil))
		},
	}
	for name, run := range seams {
		t.Run(name, func(t *testing.T) {
			injected := errors.New("injected cause")
			err := run(injected)
			var problemErr *problem.Error
			if !errors.As(err, &problemErr) || problemErr == nil {
				t.Fatalf("expected a *problem.Error, got %#v", err)
			}
			if !errors.Is(err, injected) {
				t.Fatal("errors.Is must still reach the injected cause")
			}
		})
	}
}

// TestScriptedProblemErrorPreserved proves an already problem-typed injected
// error is preserved verbatim rather than re-wrapped.
func TestScriptedProblemErrorPreserved(t *testing.T) {
	original := problem.NewError(probtest.SampleProblem())
	logger := testhelper.NewInMemoryLoggerSink()
	logger.EnqueueResult(original)
	err := logger.Emit(interfaces.NewLogRecord(time.Now(), interfaces.LogLevelInfo, "m", nil, nil, nil))
	if !errors.Is(err, original) {
		t.Fatalf("expected the original problem error preserved, got %#v", err)
	}
	probtest.AssertError(t, err, probtest.ExpectID("entity-not-found"), probtest.ExpectStatus(404))
}

func mustErr[T any](_ T, err error) error { return err }

func assertProblem(t *testing.T, err error, id string, status int) {
	t.Helper()
	probtest.AssertError(
		t, err,
		probtest.ExpectType(canonicalTypePrefix+id),
		probtest.ExpectID(id),
		probtest.ExpectStatus(status),
		probtest.ExpectData(map[string]any{"id": id}),
	)
}
