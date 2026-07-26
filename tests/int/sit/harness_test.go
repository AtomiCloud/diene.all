package sit_test

import (
	"context"
	"fmt"
	"io"
	"maps"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config"
	"github.com/AtomiCloud/diene.go-e2e/adapters/filesystem"
	"github.com/AtomiCloud/diene.go-e2e/adapters/process"
	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
	"github.com/AtomiCloud/diene.go-e2e/lib/fixture"
	"github.com/AtomiCloud/diene.go-e2e/testhelper"
)

// This is the harness proving ITSELF end to end, with nothing mocked: a fixture
// materialized onto the real filesystem, a real Go binary compiled from
// tests/fixtures/sit-artifact and driven as a real subprocess, the same journey
// run in-process, and parity asserted between the two.
//
// It is the integration-tier answer to the question the unit tier cannot ask —
// whether the compiled-artifact driver and the in-process driver actually agree
// when both are real.

// artifactSource is the materialized system under test. It lives as a .go.txt so
// the module keeps having no main package.
const artifactSource = "../../fixtures/sit-artifact/main.go.txt"

// buildArtifact compiles the stand-in system under test and returns its path.
func buildArtifact(t *testing.T) string {
	t.Helper()
	source, err := os.ReadFile(artifactSource)
	if err != nil {
		t.Fatalf("ReadFile(%q) error = %v", artifactSource, err)
	}
	workspace := t.TempDir()
	target := filepath.Join(workspace, "main.go")
	if err := os.WriteFile(target, source, 0o600); err != nil { //nolint:gosec // the path is this test's own TempDir
		t.Fatalf("WriteFile() error = %v", err)
	}
	modfile := "module example.invalid/sit-artifact\n\ngo 1.26.0\n"
	if err := os.WriteFile(filepath.Join(workspace, "go.mod"), []byte(modfile), 0o600); err != nil {
		t.Fatalf("WriteFile(go.mod) error = %v", err)
	}
	artifact := filepath.Join(workspace, "artifact")
	// Compiling the stand-in system under test is the point of this test; the
	// toolchain and the output path are both this test's own.
	build := exec.CommandContext(t.Context(), "go", "build", "-o", artifact, ".") //nolint:gosec // fixed argv into the dev-shell toolchain
	build.Dir = workspace
	build.Env = append(os.Environ(), "GOFLAGS=-mod=mod", "GOPROXY=off")
	if output, err := build.CombinedOutput(); err != nil {
		t.Fatalf("go build failed: %v\n%s", err, output)
	}
	return artifact
}

// serviceFixture is the three-layer configuration the artifact reads.
func serviceFixture(t *testing.T) fixture.Bundle {
	t.Helper()
	problems := requireProblems(t)
	bundle, err := fixture.NewBuilder(problems).
		WithApp(config.AppBlock{
			Landscape: "garden", Platform: "sulfoxide", Service: "billing",
			Module: "core", Version: "1.0.0",
		}).
		WithOverlay("garden", "app", map[string]any{"service": "billing-preview"}).
		WithSecret("postgres.MAIN.password", "injected-secret").
		Build()
	if err != nil {
		t.Fatalf("Build() error = %v", err)
	}
	return bundle
}

// requireProblems builds the harness problem factory or fails the test.
func requireProblems(t *testing.T) *e2e.Problems {
	t.Helper()
	problems, err := testhelper.SampleProblems()
	if err != nil {
		t.Fatalf("SampleProblems() error = %v", err)
	}
	return problems
}

// artifactEntrypoint is the in-process implementation of the same contract the
// compiled artifact honours: read the config file it is pointed at, read the
// secret from the environment, and exit with the requested code.
func artifactEntrypoint(_ context.Context, invocation e2e.Invocation, stdout io.Writer, stderr io.Writer) (int, error) {
	if len(invocation.Args) < 1 {
		if _, err := io.WriteString(stderr, "usage: artifact <config-path>\n"); err != nil {
			return 0, err
		}
		return 2, nil
	}
	content, readErr := os.ReadFile(invocation.Args[0]) //nolint:gosec // the test points this at its own fixture
	if readErr != nil {
		if _, err := io.WriteString(stderr, "config unreadable: "+readErr.Error()+"\n"); err != nil {
			return 0, err
		}
		return 2, nil
	}
	service := ""
	for line := range strings.SplitSeq(string(content), "\n") {
		if value, found := strings.CutPrefix(strings.TrimSpace(line), "service:"); found {
			service = strings.TrimSpace(value)
		}
	}
	if _, err := fmt.Fprintln(stdout, "service="+service); err != nil {
		return 0, err
	}
	if _, err := fmt.Fprintln(stdout, "secret="+invocation.Env["ATOMI_POSTGRES__MAIN__PASSWORD"]); err != nil {
		return 0, err
	}
	if raw := invocation.Env["E2E_ARTIFACT_EXIT"]; raw != "" {
		code, convErr := strconv.Atoi(raw)
		if convErr != nil {
			return 0, convErr
		}
		if code != 0 {
			if _, err := io.WriteString(stderr, "requested failure\n"); err != nil {
				return 0, err
			}
			return code, nil
		}
	}
	return 0, nil
}

func TestHarnessDrivesARealArtifactAndAgreesWithTheInProcessRun(t *testing.T) {
	t.Parallel()

	ctx := t.Context()
	problems := requireProblems(t)
	artifact := buildArtifact(t)

	// The fixture lands on the REAL filesystem, because a subprocess cannot read
	// an in-memory one — which is exactly why this module ships the Vfs binding.
	layout, err := serviceFixture(t).Materialize(ctx, filesystem.NewVfs(), fixture.Directory(t.TempDir(), "Sign In Then Pay"), problems)
	if err != nil {
		t.Fatalf("Materialize() error = %v", err)
	}
	if _, statErr := os.Stat(layout.OverlayPaths["garden"]); statErr != nil {
		t.Fatalf("Stat(overlay) error = %v, want the overlay on disk", statErr)
	}

	environ := serviceFixture(t).Environ(fixture.DefaultEnvPrefix)
	journey := e2e.Journey{
		Name: "reads-its-configuration",
		Steps: []e2e.Step{
			{
				Name:       "base layer",
				Invocation: e2e.Invocation{Args: []string{layout.BasePath}, Env: environ},
				Expect: e2e.Expectation{
					ExitCode:       0,
					StdoutContains: []string{"service=billing", "secret=injected-secret"},
					StdoutExcludes: []string{"service=billing-preview"},
				},
			},
			{
				Name:       "landscape overlay",
				Invocation: e2e.Invocation{Args: []string{layout.OverlayPaths["garden"]}, Env: environ},
				Expect:     e2e.Expectation{ExitCode: 0, StdoutContains: []string{"service=billing-preview"}},
			},
			{
				Name: "requested failure",
				Invocation: e2e.Invocation{
					Args: []string{layout.BasePath},
					Env:  merged(environ, map[string]string{"E2E_ARTIFACT_EXIT": "4"}),
				},
				Expect: e2e.Expectation{ExitCode: 4, StderrContains: []string{"requested failure"}},
			},
			{
				Name:       "missing argument",
				Invocation: e2e.Invocation{Env: environ},
				Expect:     e2e.Expectation{ExitCode: 2, StderrContains: []string{"usage: artifact"}},
			},
		},
	}

	compiled, err := e2e.NewCompiledDriver(e2e.CompiledOptions{
		Label:      "compiled-artifact",
		Artifact:   artifact,
		Terminal:   process.NewTerminal(process.TerminalOptions{}),
		Filesystem: filesystem.NewVfs(),
		Problems:   problems,
	})
	if err != nil {
		t.Fatalf("NewCompiledDriver() error = %v", err)
	}
	inProcess, err := e2e.NewInProcessDriver(e2e.InProcessOptions{
		Label:      "in-process",
		Entrypoint: artifactEntrypoint,
		Problems:   problems,
	})
	if err != nil {
		t.Fatalf("NewInProcessDriver() error = %v", err)
	}

	first, second, parityErr := e2e.RunParity(ctx, compiled, inProcess, journey, problems)
	if parityErr != nil {
		t.Fatalf("RunParity() error = %v", parityErr)
	}
	testhelper.AssertReport(t, first, journey)
	testhelper.AssertReport(t, second, journey)
	if first.Driver != "compiled-artifact" || second.Driver != "in-process" {
		t.Fatalf("reports = %q/%q, want one per driver", first.Driver, second.Driver)
	}
}

func TestHarnessRefusesAnArtifactThatIsNotThere(t *testing.T) {
	t.Parallel()

	problems := requireProblems(t)
	compiled, err := e2e.NewCompiledDriver(e2e.CompiledOptions{
		Artifact:   filepath.Join(t.TempDir(), "never-built"),
		Terminal:   process.NewTerminal(process.TerminalOptions{}),
		Filesystem: filesystem.NewVfs(),
		Problems:   problems,
	})
	if err != nil {
		t.Fatalf("NewCompiledDriver() error = %v", err)
	}
	_, runErr := compiled.Run(t.Context(), e2e.Invocation{})
	testhelper.AssertHarnessProblem(t, runErr, e2e.ProblemArtifactMissing)
}

// merged overlays extra onto base without mutating either.
func merged(base map[string]string, extra map[string]string) map[string]string {
	result := make(map[string]string, len(base)+len(extra))
	maps.Copy(result, base)
	maps.Copy(result, extra)
	return result
}
