package standardconfig_test

import (
	"strings"
	"testing"

	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
)

func TestValidKeyEnforcesTheUppercaseAuthoringContract(t *testing.T) {
	cases := map[string]bool{
		"MAIN":         true,
		"REPLICA":      true,
		"READ_REPLICA": true,
		"POOL_2":       true,
		"main":         false,
		"Main":         false,
		"MAIN-POOL":    false,
		"_MAIN":        false,
		"2ND":          false,
		"":             false,
		"MAIN POOL":    false,
	}
	for name, want := range cases {
		if got := standardconfig.ValidKey(name); got != want {
			t.Fatalf("ValidKey(%q) = %v, want %v", name, got, want)
		}
	}
}

func TestValidConnectionNameAcceptsAnyCasingAndRejectsUnreachableNames(t *testing.T) {
	cases := map[string]bool{
		"MAIN":         true,
		"main":         true,
		"readReplica":  true,
		"read_replica": true,
		"pool2":        true,
		"rate-limit":   false,
		"rate.limit":   false,
		"rate limit":   false,
		"2nd":          false,
		"":             false,
	}
	for name, want := range cases {
		if got := standardconfig.ValidConnectionName(name); got != want {
			t.Fatalf("ValidConnectionName(%q) = %v, want %v", name, got, want)
		}
	}
}

func TestKeysSortsSoEnumerationIsDeterministic(t *testing.T) {
	block := standardconfig.CacheBlock{"SESSION": {}, "MAIN": {}, "RATE_LIMIT": {}}
	got := standardconfig.Keys(block)
	want := []string{"MAIN", "RATE_LIMIT", "SESSION"}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Fatalf("Keys() = %v, want %v", got, want)
	}
}

func TestKeysOnAnEmptyBlockIsEmptyNotNil(t *testing.T) {
	got := standardconfig.Keys(standardconfig.StorageBlock{})
	if got == nil {
		t.Fatalf("%s", "Keys() returned nil; an empty block has no connections, not no answer")
	}
	if len(got) != 0 {
		t.Fatalf("Keys() = %v, want empty", got)
	}
}

func TestNamedResolvesADeclaredConnection(t *testing.T) {
	block := standardconfig.PostgresBlock{
		"MAIN":    {Host: "primary.invalid", Port: 5432},
		"REPLICA": {Host: "replica.invalid", Port: 5433},
	}
	entry, err := standardconfig.Named(newProblems(t, portal()), block, "REPLICA")
	if err != nil {
		t.Fatalf("Named() error = %v", err)
	}
	if entry.Host != "replica.invalid" || entry.Port != 5433 {
		t.Fatalf("Named() = %+v, want the REPLICA connection", entry)
	}
}

func TestNamedResolvesTheCanonicalisedKeyALoaderProduces(t *testing.T) {
	decoded := standardconfig.PostgresBlock{"main": {Host: "primary.lapras.invalid"}}
	entry, err := standardconfig.Named(newProblems(t, portal()), decoded, "MAIN")
	if err != nil {
		t.Fatalf("Named() error = %v; the loader lower-cases authored keys", err)
	}
	if entry.Host != "primary.lapras.invalid" {
		t.Fatalf("Named() = %+v, want the decoded connection", entry)
	}
}

func TestNamedPrefersAnExactMatchOverACaseInsensitiveOne(t *testing.T) {
	block := standardconfig.CacheBlock{
		"MAIN": {Host: "exact.invalid"},
		"main": {Host: "canonical.invalid"},
	}
	entry, err := standardconfig.Named(newProblems(t, portal()), block, "MAIN")
	if err != nil {
		t.Fatalf("Named() error = %v", err)
	}
	if entry.Host != "exact.invalid" {
		t.Fatalf("Named() = %+v, want the exactly spelled connection", entry)
	}
}

func TestNamedRefusesToGuessBetweenCaseVariants(t *testing.T) {
	block := standardconfig.CacheBlock{"main": {Host: "a.invalid"}, "Main": {Host: "b.invalid"}}
	entry, err := standardconfig.Named(newProblems(t, portal()), block, "MAIN")
	if err == nil {
		t.Fatalf("Named() picked %+v out of two case variants", entry)
	}
	raised := requireProblem(t, err)
	if !strings.HasSuffix(raised.Type, standardconfig.ProblemConnectionAmbiguous) {
		t.Fatalf("Named() problem type = %q, want the ambiguity problem", raised.Type)
	}
	matches, ok := raised.Data["matches"].([]string)
	if !ok || strings.Join(matches, ",") != "Main,main" {
		t.Fatalf("Named() matches = %v, want both variants in stable order", raised.Data["matches"])
	}
}

func TestNamedRaisesWithTheConnectionsThatDoExist(t *testing.T) {
	block := standardconfig.KvBlock{"MAIN": {Host: "kv.invalid"}, "TOKENS": {Host: "kv.invalid"}}
	entry, err := standardconfig.Named(newProblems(t, portal()), block, "SESSION")
	if err == nil {
		t.Fatalf("Named() resolved an undeclared connection: %+v", entry)
	}
	if entry.Host != "" {
		t.Fatalf("Named() returned %+v alongside an error, want the zero entry", entry)
	}
	raised := requireProblem(t, err)
	if !strings.HasSuffix(raised.Type, standardconfig.ProblemConnectionUnknown) {
		t.Fatalf("Named() problem type = %q", raised.Type)
	}
	if raised.Data["name"] != "SESSION" {
		t.Fatalf("Named() problem data = %v, want the requested name", raised.Data)
	}
	known, ok := raised.Data["known"].([]string)
	if !ok || strings.Join(known, ",") != "MAIN,TOKENS" {
		t.Fatalf("Named() problem data known = %v, want the declared connections", raised.Data["known"])
	}
}

func TestNamedWithoutAProblemFactoryStillResolvesAnUnambiguousConnection(t *testing.T) {
	entry, err := standardconfig.Named(nil, standardconfig.CacheBlock{"main": {Host: "kv.invalid"}}, "MAIN")
	if err != nil {
		t.Fatalf("Named() error = %v; a successful lookup needs no problem factory", err)
	}
	if entry.Host != "kv.invalid" {
		t.Fatalf("Named() = %+v", entry)
	}
}

func TestNamedWithoutAProblemFactoryReportsTheMissingFactory(t *testing.T) {
	_, err := standardconfig.Named(nil, standardconfig.CacheBlock{}, "MAIN")
	if err == nil {
		t.Fatalf("%s", "Named() with no problem factory returned no error")
	}
	if !strings.Contains(err.Error(), "NewProblems(portal)") {
		t.Fatalf("Named() error = %q, want it to name the remedy", err.Error())
	}
}

func TestValidateKeysAcceptsIdentifierNamesInEitherCase(t *testing.T) {
	block := standardconfig.PostgresBlock{"MAIN": {}, "read_replica": {}}
	if err := standardconfig.ValidateKeys(
		newProblems(t, portal()), standardconfig.PostgresBlockKey, block,
	); err != nil {
		t.Fatalf("ValidateKeys() error = %v; the loader lower-cases authored names", err)
	}
}

func TestValidateKeysAcceptsAnEmptyBlock(t *testing.T) {
	if err := standardconfig.ValidateKeys(
		newProblems(t, portal()), standardconfig.KvBlockKey, standardconfig.KvBlock{},
	); err != nil {
		t.Fatalf("ValidateKeys() error = %v", err)
	}
}

func TestValidateKeysReportsEveryNameWithNoReachableEnvironmentPath(t *testing.T) {
	block := standardconfig.CacheBlock{"main": {}, "rate-limit": {}, "session cache": {}}
	err := standardconfig.ValidateKeys(newProblems(t, portal()), standardconfig.CacheBlockKey, block)
	if err == nil {
		t.Fatalf("%s", "ValidateKeys() accepted connection names with no environment override path")
	}
	raised := requireProblem(t, err)
	invalid, ok := raised.Data["invalid"].([]string)
	if !ok || strings.Join(invalid, ",") != "rate-limit,session cache" {
		t.Fatalf("ValidateKeys() invalid = %v, want both offenders in stable order", raised.Data["invalid"])
	}
	if raised.Data["block"] != standardconfig.CacheBlockKey {
		t.Fatalf("ValidateKeys() block = %v, want %q", raised.Data["block"], standardconfig.CacheBlockKey)
	}
	if raised.Data["pattern"] != standardconfig.ConnectionNamePattern {
		t.Fatalf("ValidateKeys() pattern = %v, want the published pattern", raised.Data["pattern"])
	}
	if raised.Detail == nil || !strings.Contains(*raised.Detail, "rate-limit, session cache") {
		t.Fatalf("ValidateKeys() detail = %v, want it to name the offenders", raised.Detail)
	}
}

func TestValidateKeysWithoutAProblemFactoryReportsTheMissingFactory(t *testing.T) {
	err := standardconfig.ValidateKeys(nil, standardconfig.CacheBlockKey, standardconfig.CacheBlock{"x": {}})
	if err == nil {
		t.Fatalf("%s", "ValidateKeys() with no problem factory returned no error")
	}
	if !strings.HasPrefix(err.Error(), "standardconfig: ") {
		t.Fatalf("ValidateKeys() error = %q, want it namespaced to this library", err.Error())
	}
}
