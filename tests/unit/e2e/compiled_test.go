package e2e_test

import (
	"context"
	"testing"

	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
	interfacesth "github.com/AtomiCloud/diene.go-interfaces/testhelper"
)

func TestNewCompiledDriverNeedsAProblemFactory(t *testing.T) {
	t.Parallel()

	_, err := e2e.NewCompiledDriver(e2e.CompiledOptions{Artifact: "/bin/true"})
	if err == nil {
		t.Fatal("NewCompiledDriver() error = nil, want a refusal")
	}
	if got := err.Error(); got != "e2e: problems is required" {
		t.Fatalf("error = %q, want the unconfigured message", got)
	}
}

func TestNewCompiledDriverNeedsAnArtifact(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, samplePortal())
	_, err := e2e.NewCompiledDriver(e2e.CompiledOptions{Problems: problems})
	if got := problemID(t, err); got != e2e.ProblemDriverUnconfigured {
		t.Fatalf("problem id = %q, want %q", got, e2e.ProblemDriverUnconfigured)
	}
	if problemData(t, err)["component"] != "artifact" {
		t.Fatalf("problem data = %v, want the artifact component", problemData(t, err))
	}
}

func TestNewCompiledDriverNeedsATerminal(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, samplePortal())
	_, err := e2e.NewCompiledDriver(e2e.CompiledOptions{Artifact: "/bin/true", Problems: problems})
	if got := problemID(t, err); got != e2e.ProblemDriverUnconfigured {
		t.Fatalf("problem id = %q, want %q", got, e2e.ProblemDriverUnconfigured)
	}
	if problemData(t, err)["component"] != "terminal" {
		t.Fatalf("problem data = %v, want the terminal component", problemData(t, err))
	}
}

func TestCompiledDriverDefaultsItsLabel(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, samplePortal())
	driver, err := e2e.NewCompiledDriver(e2e.CompiledOptions{
		Artifact: "/opt/app/bin/app",
		Terminal: interfacesth.NewInMemoryTerminal(),
		Problems: problems,
	})
	if err != nil {
		t.Fatalf("NewCompiledDriver() error = %v", err)
	}
	if driver.Name() != e2e.DefaultCompiledLabel {
		t.Fatalf("Name() = %q, want %q", driver.Name(), e2e.DefaultCompiledLabel)
	}
	if driver.Artifact() != "/opt/app/bin/app" {
		t.Fatalf("Artifact() = %q, want the configured path", driver.Artifact())
	}
}

func TestCompiledDriverRunsTheArtifactThroughTheTerminalSeam(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, samplePortal())
	terminal := interfacesth.NewInMemoryTerminal()
	terminal.EnqueueResult(interfaces.TerminalOutput{ExitCode: 0, Stdout: "ready", Stderr: ""}, nil)
	driver, err := e2e.NewCompiledDriver(e2e.CompiledOptions{
		Label:            "artifact",
		Artifact:         "/opt/app/bin/app",
		Terminal:         terminal,
		Environment:      map[string]string{"BASE": "one", "SHARED": "base"},
		WorkingDirectory: "/srv",
		Problems:         problems,
	})
	if err != nil {
		t.Fatalf("NewCompiledDriver() error = %v", err)
	}
	result, err := driver.Run(context.Background(), e2e.Invocation{
		Args: []string{"migrate", "--yes"},
		Env:  map[string]string{"SHARED": "overlay"},
	})
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	if !result.Succeeded() || result.Stdout != "ready" {
		t.Fatalf("Run() = %+v, want a clean run with stdout ready", result)
	}
	commands := terminal.Commands()
	if len(commands) != 1 {
		t.Fatalf("terminal saw %d commands, want 1", len(commands))
	}
	command := commands[0]
	if command.Executable != "/opt/app/bin/app" {
		t.Fatalf("executable = %q, want the artifact", command.Executable)
	}
	if len(command.Args) != 2 || command.Args[0] != "migrate" {
		t.Fatalf("args = %v, want the invocation arguments", command.Args)
	}
	if command.WorkingDirectory == nil || *command.WorkingDirectory != "/srv" {
		t.Fatalf("working directory = %v, want /srv", command.WorkingDirectory)
	}
	if command.Environment["BASE"] != "one" {
		t.Fatalf("environment = %v, want the driver base preserved", command.Environment)
	}
	if command.Environment["SHARED"] != "overlay" {
		t.Fatalf("environment = %v, want the invocation to win over the base", command.Environment)
	}
	if !command.IncludeParentEnvironment || command.RunInShell {
		t.Fatalf("command = %+v, want an inherited, non-shell invocation", command)
	}
}

func TestCompiledDriverHonoursAPerStepWorkingDirectory(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, samplePortal())
	terminal := interfacesth.NewInMemoryTerminal()
	terminal.EnqueueResult(interfaces.TerminalOutput{ExitCode: 7, Stdout: "", Stderr: "nope"}, nil)
	driver, err := e2e.NewCompiledDriver(e2e.CompiledOptions{
		Artifact: "/opt/app/bin/app",
		Terminal: terminal,
		Problems: problems,
	})
	if err != nil {
		t.Fatalf("NewCompiledDriver() error = %v", err)
	}
	result, err := driver.Run(context.Background(), e2e.Invocation{WorkingDirectory: "/tmp/case"})
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	if result.ExitCode != 7 || result.Succeeded() {
		t.Fatalf("Run() = %+v, want a failing exit code reported as a result", result)
	}
	if got := terminal.Commands()[0].WorkingDirectory; got == nil || *got != "/tmp/case" {
		t.Fatalf("working directory = %v, want /tmp/case", got)
	}
}

func TestCompiledDriverLeavesABlankWorkingDirectoryAbsent(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, samplePortal())
	terminal := interfacesth.NewInMemoryTerminal()
	terminal.EnqueueResult(interfaces.TerminalOutput{}, nil)
	driver, err := e2e.NewCompiledDriver(e2e.CompiledOptions{
		Artifact: "/opt/app/bin/app",
		Terminal: terminal,
		Problems: problems,
	})
	if err != nil {
		t.Fatalf("NewCompiledDriver() error = %v", err)
	}
	if _, err := driver.Run(context.Background(), e2e.Invocation{}); err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	if got := terminal.Commands()[0].WorkingDirectory; got != nil {
		t.Fatalf("working directory = %v, want the absent value", *got)
	}
}

func TestCompiledDriverReportsATerminalFailureAsAProblem(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, samplePortal())
	terminal := interfacesth.NewInMemoryTerminal()
	terminal.EnqueueResult(interfaces.TerminalOutput{}, errBoom)
	driver, err := e2e.NewCompiledDriver(e2e.CompiledOptions{
		Artifact: "/opt/app/bin/app",
		Terminal: terminal,
		Problems: problems,
	})
	if err != nil {
		t.Fatalf("NewCompiledDriver() error = %v", err)
	}
	_, runErr := driver.Run(context.Background(), e2e.Invocation{})
	if got := problemID(t, runErr); got != e2e.ProblemInvocationFailed {
		t.Fatalf("problem id = %q, want %q", got, e2e.ProblemInvocationFailed)
	}
	if problemData(t, runErr)["artifact"] != "/opt/app/bin/app" {
		t.Fatalf("problem data = %v, want the artifact named", problemData(t, runErr))
	}
}

func TestCompiledDriverProvesTheArtifactExistsFirst(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, samplePortal())
	terminal := interfacesth.NewInMemoryTerminal()
	filesystem := interfacesth.NewInMemoryVfs(interfacesth.InMemoryVfsOptions{
		Files: map[string][]byte{"/opt/app/bin/app": []byte("ELF")},
	})
	terminal.EnqueueResult(interfaces.TerminalOutput{Stdout: "ok"}, nil)
	driver, err := e2e.NewCompiledDriver(e2e.CompiledOptions{
		Artifact:   "/opt/app/bin/app",
		Terminal:   terminal,
		Filesystem: filesystem,
		Problems:   problems,
	})
	if err != nil {
		t.Fatalf("NewCompiledDriver() error = %v", err)
	}
	if _, err := driver.Run(context.Background(), e2e.Invocation{}); err != nil {
		t.Fatalf("Run() error = %v", err)
	}
}

func TestCompiledDriverRefusesAMissingArtifact(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, samplePortal())
	terminal := interfacesth.NewInMemoryTerminal()
	filesystem := interfacesth.NewInMemoryVfs(interfacesth.InMemoryVfsOptions{})
	driver, err := e2e.NewCompiledDriver(e2e.CompiledOptions{
		Artifact:   "/opt/app/bin/app",
		Terminal:   terminal,
		Filesystem: filesystem,
		Problems:   problems,
	})
	if err != nil {
		t.Fatalf("NewCompiledDriver() error = %v", err)
	}
	_, runErr := driver.Run(context.Background(), e2e.Invocation{})
	if got := problemID(t, runErr); got != e2e.ProblemArtifactMissing {
		t.Fatalf("problem id = %q, want %q", got, e2e.ProblemArtifactMissing)
	}
	if len(terminal.Commands()) != 0 {
		t.Fatalf("terminal ran %d commands, want none", len(terminal.Commands()))
	}
}

func TestCompiledDriverReportsAnUninspectableArtifact(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t, samplePortal())
	filesystem := interfacesth.NewInMemoryVfs(interfacesth.InMemoryVfsOptions{})
	filesystem.EnqueueExistsResult(false, errBoom)
	driver, err := e2e.NewCompiledDriver(e2e.CompiledOptions{
		Artifact:   "/opt/app/bin/app",
		Terminal:   interfacesth.NewInMemoryTerminal(),
		Filesystem: filesystem,
		Problems:   problems,
	})
	if err != nil {
		t.Fatalf("NewCompiledDriver() error = %v", err)
	}
	_, runErr := driver.Run(context.Background(), e2e.Invocation{})
	if got := problemID(t, runErr); got != e2e.ProblemArtifactMissing {
		t.Fatalf("problem id = %q, want %q", got, e2e.ProblemArtifactMissing)
	}
}
