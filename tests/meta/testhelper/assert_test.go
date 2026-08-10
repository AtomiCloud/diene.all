package testhelper_test

import (
	"errors"
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
	"github.com/AtomiCloud/diene.go-standard-config/testhelper"
)

// Assert-the-asserter: every shipped assertion is proven to pass on known-good
// input and to fail on known-bad. An assertion that cannot fail is decoration.

func TestRequireStartedPassesOnAStartedPreset(t *testing.T) {
	spy := &recorder{}
	started := testhelper.RequireStarted(spy, &testhelper.StartedCache{Key: "MAIN"}, nil)
	if spy.failed() {
		t.Fatalf("RequireStarted() failed on a started preset: %v", spy.failures)
	}
	if started == nil || started.Key != "MAIN" {
		t.Fatalf("RequireStarted() = %v, want the handle it was given", started)
	}
	if spy.helped == 0 {
		t.Fatalf("%s", "RequireStarted() did not mark itself a helper; failures would point at the wrong line")
	}
}

func TestRequireStartedFailsOnAStartError(t *testing.T) {
	spy := &recorder{}
	started := testhelper.RequireStarted(spy, (*testhelper.StartedPostgres)(nil), errors.New("no daemon"))
	if started != nil {
		t.Fatalf("RequireStarted() returned %v after a failure", started)
	}
	if !strings.Contains(spy.only(t), "no daemon") {
		t.Fatalf("RequireStarted() failure = %q, want it to carry the cause", spy.only(t))
	}
}

func TestRequireStartedFailsOnANilHandleWithNoError(t *testing.T) {
	spy := &recorder{}
	started := testhelper.RequireStarted(spy, (*testhelper.StartedKv)(nil), nil)
	if started != nil {
		t.Fatalf("RequireStarted() returned %v for a nil handle", started)
	}
	if !strings.Contains(spy.only(t), "nil with no error") {
		t.Fatalf("RequireStarted() failure = %q", spy.only(t))
	}
}

func TestRequireEntryPassesOnADeclaredConnection(t *testing.T) {
	spy := &recorder{}
	entry := testhelper.RequireEntry(spy, testhelper.FakePostgres("MAIN"), "MAIN")
	if spy.failed() {
		t.Fatalf("RequireEntry() failed on a declared connection: %v", spy.failures)
	}
	if entry.Port != 5432 {
		t.Fatalf("RequireEntry() = %+v", entry)
	}
}

func TestRequireEntryFailsOnAnAbsentConnectionAndNamesTheOnesPresent(t *testing.T) {
	spy := &recorder{}
	entry := testhelper.RequireEntry(spy, testhelper.FakeKv("TOKENS"), "SESSION")
	if entry.Host != "" {
		t.Fatalf("RequireEntry() returned %+v after a failure, want the zero entry", entry)
	}
	failure := spy.only(t)
	if !strings.Contains(failure, `"SESSION"`) || !strings.Contains(failure, "TOKENS") {
		t.Fatalf("RequireEntry() failure = %q, want the missing and the known names", failure)
	}
}

func TestRequireUppercaseKeysPassesOnAnAuthoredBlock(t *testing.T) {
	spy := &recorder{}
	testhelper.RequireUppercaseKeys(spy, testhelper.FakeStorage("READ_ONLY"))
	if spy.failed() {
		t.Fatalf("RequireUppercaseKeys() failed on an UPPERCASE block: %v", spy.failures)
	}
}

func TestRequireUppercaseKeysFailsOnALowerCaseName(t *testing.T) {
	spy := &recorder{}
	testhelper.RequireUppercaseKeys(spy, standardconfig.CacheBlock{"main": {}})
	if !strings.Contains(spy.only(t), standardconfig.UppercaseKeyPattern) {
		t.Fatalf("RequireUppercaseKeys() failure = %q, want the published pattern", spy.only(t))
	}
}

func TestRequireUppercaseKeysReportsOnlyTheFirstOffender(t *testing.T) {
	spy := &recorder{}
	testhelper.RequireUppercaseKeys(spy, standardconfig.CacheBlock{"aaa": {}, "bbb": {}})
	failure := spy.only(t)
	if !strings.Contains(failure, `"aaa"`) {
		t.Fatalf("RequireUppercaseKeys() reported %q, want the first offender in stable order", failure)
	}
}

func TestRequireConnectionNamesPassesOnADecodedBlock(t *testing.T) {
	spy := &recorder{}
	testhelper.RequireConnectionNames(spy, standardconfig.PostgresBlock{"main": {}, "read_replica": {}})
	if spy.failed() {
		t.Fatalf("RequireConnectionNames() failed on a decoded block: %v", spy.failures)
	}
}

func TestRequireConnectionNamesFailsOnAnUnreachableName(t *testing.T) {
	spy := &recorder{}
	testhelper.RequireConnectionNames(spy, standardconfig.KvBlock{"rate-limit": {}})
	failure := spy.only(t)
	if !strings.Contains(failure, standardconfig.ConnectionNamePattern) {
		t.Fatalf("RequireConnectionNames() failure = %q, want the published pattern", failure)
	}
	if !strings.Contains(failure, "unreachable") {
		t.Fatalf("RequireConnectionNames() failure = %q, want it to say why the name is rejected", failure)
	}
}
