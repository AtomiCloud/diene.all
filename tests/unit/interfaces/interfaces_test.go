package interfaces_test

import (
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-interfaces/lib/interfaces"
)

func TestVfsValues(t *testing.T) {
	modified := time.Date(2026, 7, 22, 1, 2, 3, 0, time.FixedZone("offset", 3600))
	entry := interfaces.NewVfsEntry("/a", interfaces.VfsEntryTypeFile, 4, &modified)
	modified = time.Time{}
	if entry.Path != "/a" || entry.Type != interfaces.VfsEntryTypeFile || entry.Size != 4 || entry.ModifiedAt == nil || entry.ModifiedAt.Location() != time.UTC {
		t.Fatalf("unexpected entry: %#v", entry)
	}
	if got := interfaces.NewVfsEntry("/", interfaces.VfsEntryTypeDirectory, 0, nil); got.ModifiedAt != nil {
		t.Fatalf("expected nil modified time: %#v", got)
	}
	for _, entryType := range []interfaces.VfsEntryType{interfaces.VfsEntryTypeFile, interfaces.VfsEntryTypeDirectory, interfaces.VfsEntryTypeLink} {
		if entryType.String() == "" {
			t.Fatal("entry type string must be non-empty")
		}
	}
}

func TestTerminalCommandClonesInputs(t *testing.T) {
	directory := "/tmp"
	args := []string{"one"}
	environment := map[string]string{"A": "1"}
	command := interfaces.NewTerminalCommand("tool", args, &directory, environment, true, true)
	args[0], environment["A"], directory = "two", "2", "/other"
	if command.Args[0] != "one" || command.Environment["A"] != "1" || *command.WorkingDirectory != "/tmp" {
		t.Fatalf("constructor did not clone: %#v", command)
	}
	cloned := command.Clone()
	cloned.Args[0], cloned.Environment["A"] = "changed", "changed"
	if command.Args[0] != "one" || command.Environment["A"] != "1" {
		t.Fatalf("clone aliases command: %#v", command)
	}
	if !(interfaces.TerminalOutput{}).Succeeded() || (interfaces.TerminalOutput{ExitCode: 1}).Succeeded() {
		t.Fatal("unexpected terminal success result")
	}
	withoutOptional := interfaces.NewTerminalCommand("tool", nil, nil, nil, false, false)
	if withoutOptional.WorkingDirectory != nil || len(withoutOptional.Args) != 0 || len(withoutOptional.Environment) != 0 {
		t.Fatalf("unexpected optional command fields: %#v", withoutOptional)
	}
}

func TestLogRecordCopiesInputs(t *testing.T) {
	message, stack := "failure", "stack"
	attributes := map[string]any{"attempt": 1}
	record := interfaces.NewLogRecord(time.Date(2026, 7, 22, 1, 2, 3, 0, time.FixedZone("offset", 3600)), interfaces.LogLevelWarning, "retry", attributes, &message, &stack)
	attributes["attempt"], message, stack = 2, "changed", "changed"
	if record.Timestamp.Location() != time.UTC || record.Attributes["attempt"] != 1 || *record.Error != "failure" || *record.StackTrace != "stack" {
		t.Fatalf("record was not copied: %#v", record)
	}
	clone := record.Clone()
	clone.Attributes["attempt"] = 3
	if record.Attributes["attempt"] != 1 {
		t.Fatal("record clone aliases attributes")
	}
	if len(interfaces.CloneAttributes(nil)) != 0 {
		t.Fatal("nil attributes must become an empty map")
	}
	for _, level := range []interfaces.LogLevel{interfaces.LogLevelTrace, interfaces.LogLevelDebug, interfaces.LogLevelInfo, interfaces.LogLevelWarning, interfaces.LogLevelError, interfaces.LogLevelFatal} {
		if level.String() == "" {
			t.Fatal("log level string must be non-empty")
		}
	}
}

func TestMetricRecordCopiesInputs(t *testing.T) {
	unit := "ms"
	attributes := map[string]any{"route": "/"}
	record := interfaces.NewMetricRecord(time.Date(2026, 7, 22, 1, 2, 3, 0, time.FixedZone("offset", 3600)), "latency", interfaces.MetricKindHistogram, 2.5, &unit, attributes)
	unit, attributes["route"] = "s", "/changed"
	if record.Timestamp.Location() != time.UTC || *record.Unit != "ms" || record.Attributes["route"] != "/" {
		t.Fatalf("metric was not copied: %#v", record)
	}
	clone := record.Clone()
	clone.Attributes["route"] = "/clone"
	if record.Attributes["route"] != "/" {
		t.Fatal("metric clone aliases attributes")
	}
	for _, kind := range []interfaces.MetricKind{interfaces.MetricKindCounter, interfaces.MetricKindGauge, interfaces.MetricKindHistogram} {
		if kind.String() == "" {
			t.Fatal("metric kind string must be non-empty")
		}
	}
}
