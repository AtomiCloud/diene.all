package testhelper_test

import (
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
	"github.com/AtomiCloud/diene.go-errors-problems/testhelper"
)

func TestSampleErrorPortalIsValid(t *testing.T) {
	t.Parallel()
	uri, err := problem.TypeURI(testhelper.SampleErrorPortal(), "v1", "entity-not-found")
	if err != nil {
		t.Fatalf("sample portal should be valid: %v", err)
	}
	if !strings.HasPrefix(uri, "https://") || !strings.Contains(uri, "/docs/") {
		t.Fatalf("unexpected sample URI: %q", uri)
	}
}

func TestSampleProblemMintsSingleSourceURI(t *testing.T) {
	t.Parallel()
	sample := testhelper.SampleProblem()
	want := "https://docs.raichu.cluster.atomi.cloud/docs/raichu/go/user/api/v1/entity-not-found"
	if sample.Type != want {
		t.Fatalf("sample type = %q, want %q", sample.Type, want)
	}
	if sample.Status != 404 || sample.Title != "Entity not found" {
		t.Fatalf("unexpected sample fields: %+v", sample)
	}
	if err := testhelper.CheckProblem(sample, testhelper.ExpectID("entity-not-found"), testhelper.ExpectStatus(404)); err != nil {
		t.Fatalf("sample should satisfy its own matcher: %v", err)
	}
}
