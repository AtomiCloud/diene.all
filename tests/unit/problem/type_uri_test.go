package problem_test

import (
	"errors"
	"testing"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

func TestTypeURIExpandsTemplate(t *testing.T) {
	t.Parallel()
	portal := problem.ErrorPortal{
		Scheme:    "https",
		Host:      "docs.raichu.cluster.atomi.cloud",
		Landscape: "raichu",
		Platform:  "go",
		Service:   "user",
		Module:    "api",
	}
	got, err := problem.TypeURI(portal, "v1", "entity-not-found")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := "https://docs.raichu.cluster.atomi.cloud/docs/raichu/go/user/api/v1/entity-not-found"
	if got != want {
		t.Fatalf("TypeURI = %q, want %q", got, want)
	}
}

func TestTypeURIRejectsEmptySegment(t *testing.T) {
	t.Parallel()
	portal := problem.LocalErrorPortal()
	_, err := problem.TypeURI(portal, "", "id")
	var segmentErr *problem.InvalidSegmentError
	if !errors.As(err, &segmentErr) {
		t.Fatalf("expected *InvalidSegmentError, got %v", err)
	}
	if segmentErr.Name != "version" {
		t.Fatalf("expected version segment error, got %q", segmentErr.Name)
	}
	if segmentErr.Error() == "" {
		t.Fatal("error message should not be empty")
	}
}

func TestTypeURIRejectsSlashSegment(t *testing.T) {
	t.Parallel()
	portal := problem.LocalErrorPortal()
	_, err := problem.TypeURI(portal, "v1", "bad/id")
	var segmentErr *problem.InvalidSegmentError
	if !errors.As(err, &segmentErr) {
		t.Fatalf("expected *InvalidSegmentError, got %v", err)
	}
	if segmentErr.Name != "id" || segmentErr.Value != "bad/id" {
		t.Fatalf("unexpected segment error: %+v", segmentErr)
	}
}

func TestTypeURIRejectsUnsafeSegments(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name   string
		mutate func(*problem.ErrorPortal)
		id     string
		want   string
	}{
		{name: "scheme", mutate: func(portal *problem.ErrorPortal) { portal.Scheme = "ht:tp" }, id: "id", want: "scheme"},
		{name: "host", mutate: func(portal *problem.ErrorPortal) { portal.Host = "bad host" }, id: "id", want: "host"},
		{name: "path query", mutate: func(_ *problem.ErrorPortal) {}, id: "bad?id", want: "id"},
		{name: "path fragment", mutate: func(_ *problem.ErrorPortal) {}, id: "bad#id", want: "id"},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			t.Parallel()
			portal := problem.LocalErrorPortal()
			testCase.mutate(&portal)
			_, err := problem.TypeURI(portal, "v1", testCase.id)
			var segmentErr *problem.InvalidSegmentError
			if !errors.As(err, &segmentErr) {
				t.Fatalf("expected *InvalidSegmentError, got %v", err)
			}
			if segmentErr.Name != testCase.want {
				t.Fatalf("segment = %q, want %q", segmentErr.Name, testCase.want)
			}
		})
	}
}

func TestLocalErrorPortalIsValid(t *testing.T) {
	t.Parallel()
	if _, err := problem.TypeURI(problem.LocalErrorPortal(), "v1", "local-error"); err != nil {
		t.Fatalf("local portal should be valid: %v", err)
	}
}
