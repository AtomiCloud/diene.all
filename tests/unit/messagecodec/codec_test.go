package messagecodec_test

import (
	"errors"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-consumer/lib/messagecodec"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

func TestEncodeDecodeWorkerMessage(t *testing.T) {
	t.Parallel()
	createdAt := time.Date(2026, time.July, 25, 14, 30, 0, 123, time.FixedZone("SGT", 8*60*60))
	message := messagecodec.WorkerMessage{
		ID: "11d8ab19-cdc7-4bc4-a178-70a352c352e8", CreatedAt: createdAt, Payload: "",
	}

	encoded, err := messagecodec.Encode(message)
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	actual, err := messagecodec.Decode(encoded)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	if actual.ID != message.ID || actual.Payload != message.Payload {
		t.Fatalf("decoded message = %#v", actual)
	}
	if actual.CreatedAt.Location() != time.UTC || !actual.CreatedAt.Equal(createdAt) {
		t.Fatalf("decoded instant = %s, want UTC equivalent of %s", actual.CreatedAt, createdAt)
	}
}

func TestEncodeRejectsInvalidMessages(t *testing.T) {
	t.Parallel()
	validTime := time.Date(2026, time.July, 25, 6, 30, 0, 0, time.UTC)
	tests := []messagecodec.WorkerMessage{
		{ID: "short", CreatedAt: validTime},
		{ID: "11d8ab19xcdc7-4bc4-a178-70a352c352e8", CreatedAt: validTime},
		{ID: "11d8ab19-cdc7-4bc4-a178-70a352c352eg", CreatedAt: validTime},
		{ID: "11d8ab19-cdc7-4bc4-a178-70a352c352e8", CreatedAt: time.Time{}},
	}
	for _, message := range tests {
		_, err := messagecodec.Encode(message)
		assertProblem(t, err)
	}
}

func TestDecodeRejectsInvalidWireValues(t *testing.T) {
	t.Parallel()
	tests := []string{
		"not-json",
		`{"id":"11d8ab19-cdc7-4bc4-a178-70a352c352e8","createdAt":"2026-07-25T06:30:00Z","payload":"ok","extra":true}`,
		`{"id":"11d8ab19-cdc7-4bc4-a178-70a352c352e8","createdAt":"2026-07-25T06:30:00Z","payload":"ok"}{}`,
		`{"id":"11d8ab19-cdc7-4bc4-a178-70a352c352e8","createdAt":"2026-07-25T06:30:00Z"}`,
		`{"id":"11d8ab19-cdc7-4bc4-a178-70a352c352e8","createdAt":"yesterday","payload":"ok"}`,
		`{"id":"not-a-uuid","createdAt":"2026-07-25T06:30:00Z","payload":"ok"}`,
	}
	for _, input := range tests {
		_, err := messagecodec.Decode(input)
		assertProblem(t, err)
	}
}

func assertProblem(t *testing.T, err error) {
	t.Helper()
	if err == nil {
		t.Fatal("expected an error")
	}
	var carried *problem.Error
	if !errors.As(err, &carried) {
		t.Fatalf("error is not problem typed: %T %v", err, err)
	}
}
