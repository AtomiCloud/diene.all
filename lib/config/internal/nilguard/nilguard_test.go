package nilguard_test

import (
	"testing"

	"github.com/AtomiCloud/diene.go-config/lib/config/internal/nilguard"
)

type source interface{ Name() string }

type concrete struct{}

func (*concrete) Name() string { return "concrete" }

func TestIsNilDetectsUntypedAndTypedNils(t *testing.T) {
	t.Parallel()
	var typedPointer *concrete
	var typedInterface source
	nilCases := []any{
		nil,
		typedPointer,
		typedInterface,
		map[string]string(nil),
		[]string(nil),
		(func())(nil),
		(chan int)(nil),
	}
	for index, value := range nilCases {
		if !nilguard.IsNil(value) {
			t.Fatalf("case %d must be nil", index)
		}
	}
}

func TestIsNilRejectsLiveValues(t *testing.T) {
	t.Parallel()
	liveCases := []any{
		&concrete{},
		source(&concrete{}),
		map[string]string{},
		[]string{},
		"scalar",
		0,
	}
	for index, value := range liveCases {
		if nilguard.IsNil(value) {
			t.Fatalf("case %d must not be nil", index)
		}
	}
}
