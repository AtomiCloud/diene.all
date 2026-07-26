package dbinit_test

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-consumer/lib/dbinit"
)

type probeFake struct {
	name  string
	calls *[]string
	err   error
}

func (f *probeFake) Ping(context.Context) error {
	*f.calls = append(*f.calls, f.name)
	return f.err
}

type bucketFake struct {
	name  string
	calls *[]string
	err   error
}

func (f *bucketFake) EnsureBucket(context.Context) error {
	*f.calls = append(*f.calls, f.name)
	return f.err
}

func TestValidateProbes(t *testing.T) {
	t.Parallel()

	calls := []string{}
	valid := []dbinit.NamedProbe{{Name: "MAIN", Probe: &probeFake{name: "main", calls: &calls}}}
	if err := dbinit.ValidateProbes("postgres", valid); err != nil {
		t.Fatalf("ValidateProbes() error = %v", err)
	}
	if err := dbinit.ValidateProbes("postgres", []dbinit.NamedProbe{{Name: " ", Probe: valid[0].Probe}}); err == nil || !strings.Contains(err.Error(), "probe 0 has no name") {
		t.Fatalf("ValidateProbes() blank-name error = %v", err)
	}
	if err := dbinit.ValidateProbes("postgres", []dbinit.NamedProbe{{Name: "MAIN"}}); err == nil || !strings.Contains(err.Error(), "probe \"MAIN\" is required") {
		t.Fatalf("ValidateProbes() nil-probe error = %v", err)
	}
}

func TestNewReachabilityChecksValidatesEveryGroup(t *testing.T) {
	t.Parallel()

	calls := []string{}
	valid := dbinit.NamedProbe{Name: "MAIN", Probe: &probeFake{name: "main", calls: &calls}}
	tests := []struct {
		name    string
		options dbinit.ReachabilityOptions
		want    string
	}{
		{"postgres", dbinit.ReachabilityOptions{Postgres: []dbinit.NamedProbe{{Name: ""}}}, "postgres probe 0 has no name"},
		{"redis", dbinit.ReachabilityOptions{Postgres: []dbinit.NamedProbe{valid}, Redis: []dbinit.NamedProbe{{Name: "MAIN"}}}, "redis probe \"MAIN\" is required"},
		{"storage", dbinit.ReachabilityOptions{Postgres: []dbinit.NamedProbe{valid}, Redis: []dbinit.NamedProbe{valid}, Storage: []dbinit.NamedProbe{{Name: ""}}}, "storage probe 0 has no name"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			if _, err := dbinit.NewReachabilityChecks(test.options); err == nil || !strings.Contains(err.Error(), test.want) {
				t.Fatalf("NewReachabilityChecks() error = %v, want containing %q", err, test.want)
			}
		})
	}
}

func TestReachabilityChecksRunInDependencyOrder(t *testing.T) {
	t.Parallel()

	calls := []string{}
	postgres := []dbinit.NamedProbe{{Name: "PG1", Probe: &probeFake{name: "postgres-one", calls: &calls}}, {Name: "PG2", Probe: &probeFake{name: "postgres-two", calls: &calls}}}
	redis := []dbinit.NamedProbe{{Name: "REDIS", Probe: &probeFake{name: "redis", calls: &calls}}}
	storage := []dbinit.NamedProbe{{Name: "S3", Probe: &probeFake{name: "storage", calls: &calls}}}
	subject, err := dbinit.NewReachabilityChecks(dbinit.ReachabilityOptions{Postgres: postgres, Redis: redis, Storage: storage})
	if err != nil {
		t.Fatalf("NewReachabilityChecks() error = %v", err)
	}
	postgres[0] = dbinit.NamedProbe{Name: "MUTATED", Probe: &probeFake{name: "mutated", calls: &calls}}

	if err := subject.Run(context.Background()); err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	if actual := strings.Join(calls, ","); actual != "postgres-one,postgres-two,redis,storage" {
		t.Fatalf("probe order = %q", actual)
	}
}

func TestReachabilityChecksStopAtEachFailedGroup(t *testing.T) {
	t.Parallel()

	want := errors.New("dependency unavailable")
	tests := []struct {
		name        string
		postgresErr error
		redisErr    error
		storageErr  error
		wantCalls   string
		wantKind    string
	}{
		{"postgres", want, nil, nil, "postgres", "postgres"},
		{"redis", nil, want, nil, "postgres,redis", "redis"},
		{"storage", nil, nil, want, "postgres,redis,storage", "storage"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			calls := []string{}
			subject, err := dbinit.NewReachabilityChecks(dbinit.ReachabilityOptions{
				Postgres: []dbinit.NamedProbe{{Name: "MAIN", Probe: &probeFake{name: "postgres", calls: &calls, err: test.postgresErr}}},
				Redis:    []dbinit.NamedProbe{{Name: "MAIN", Probe: &probeFake{name: "redis", calls: &calls, err: test.redisErr}}},
				Storage:  []dbinit.NamedProbe{{Name: "MAIN", Probe: &probeFake{name: "storage", calls: &calls, err: test.storageErr}}},
			})
			if err != nil {
				t.Fatalf("NewReachabilityChecks() error = %v", err)
			}
			runErr := subject.Run(context.Background())
			if !errors.Is(runErr, want) || !strings.Contains(runErr.Error(), test.wantKind) {
				t.Fatalf("Run() error = %v, want wrapping %v for %s", runErr, want, test.wantKind)
			}
			if actual := strings.Join(calls, ","); actual != test.wantCalls {
				t.Fatalf("probe calls = %q, want %q", actual, test.wantCalls)
			}
		})
	}
}

func TestRunProbesAcceptsAnEmptyGroup(t *testing.T) {
	t.Parallel()

	if err := dbinit.RunProbes(context.Background(), "empty", nil); err != nil {
		t.Fatalf("RunProbes() error = %v", err)
	}
}

func TestNewBucketCreatorValidatesBuckets(t *testing.T) {
	t.Parallel()

	calls := []string{}
	if _, err := dbinit.NewBucketCreator(true, []dbinit.NamedBucket{{Name: " ", Provisioner: &bucketFake{calls: &calls}}}); err == nil || !strings.Contains(err.Error(), "bucket 0 has no name") {
		t.Fatalf("NewBucketCreator() blank-name error = %v", err)
	}
	if _, err := dbinit.NewBucketCreator(true, []dbinit.NamedBucket{{Name: "MAIN"}}); err == nil || !strings.Contains(err.Error(), "bucket provisioner \"MAIN\" is required") {
		t.Fatalf("NewBucketCreator() nil-provisioner error = %v", err)
	}
}

func TestBucketCreatorHonorsDisabledFlag(t *testing.T) {
	t.Parallel()

	calls := []string{}
	subject, err := dbinit.NewBucketCreator(false, []dbinit.NamedBucket{{Name: "MAIN", Provisioner: &bucketFake{name: "main", calls: &calls, err: errors.New("must not run")}}})
	if err != nil {
		t.Fatalf("NewBucketCreator() error = %v", err)
	}
	if err := subject.Run(context.Background()); err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	if len(calls) != 0 {
		t.Fatalf("bucket calls = %#v", calls)
	}
}

func TestBucketCreatorRunsInOrderAndOwnsInput(t *testing.T) {
	t.Parallel()

	calls := []string{}
	buckets := []dbinit.NamedBucket{
		{Name: "MAIN", Provisioner: &bucketFake{name: "main", calls: &calls}},
		{Name: "ARCHIVE", Provisioner: &bucketFake{name: "archive", calls: &calls}},
	}
	subject, err := dbinit.NewBucketCreator(true, buckets)
	if err != nil {
		t.Fatalf("NewBucketCreator() error = %v", err)
	}
	buckets[0] = dbinit.NamedBucket{Name: "MUTATED", Provisioner: &bucketFake{name: "mutated", calls: &calls}}
	if err := subject.Run(context.Background()); err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	if actual := strings.Join(calls, ","); actual != "main,archive" {
		t.Fatalf("bucket order = %q", actual)
	}
}

func TestBucketCreatorStopsOnFailure(t *testing.T) {
	t.Parallel()

	calls := []string{}
	want := errors.New("bucket unavailable")
	subject, err := dbinit.NewBucketCreator(true, []dbinit.NamedBucket{
		{Name: "MAIN", Provisioner: &bucketFake{name: "main", calls: &calls, err: want}},
		{Name: "ARCHIVE", Provisioner: &bucketFake{name: "archive", calls: &calls}},
	})
	if err != nil {
		t.Fatalf("NewBucketCreator() error = %v", err)
	}
	runErr := subject.Run(context.Background())
	if !errors.Is(runErr, want) || !strings.Contains(runErr.Error(), "MAIN") {
		t.Fatalf("Run() error = %v, want wrapping %v", runErr, want)
	}
	if actual := strings.Join(calls, ","); actual != "main" {
		t.Fatalf("bucket calls = %q", actual)
	}
}
