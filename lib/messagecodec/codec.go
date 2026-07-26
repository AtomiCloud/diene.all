package messagecodec

import (
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

const (
	problemVersion        = "v1"
	problemInvalidMessage = "invalid-worker-message"
)

// WorkerMessage is the validated domain form of one worker message.
type WorkerMessage struct {
	ID        string
	CreatedAt time.Time
	Payload   string
}

// StreamEnvelope is one transport message awaiting decoding and acknowledgement.
type StreamEnvelope struct {
	ID      string
	Payload string
}

type encodedMessage struct {
	CreatedAt string `json:"createdAt"`
	ID        string `json:"id"`
	Payload   string `json:"payload"`
}

type decodedMessage struct {
	CreatedAt *string `json:"createdAt"`
	ID        *string `json:"id"`
	Payload   *string `json:"payload"`
}

// Encode validates message and serializes its canonical wire form.
func Encode(message WorkerMessage) (string, error) {
	message.CreatedAt = message.CreatedAt.UTC()
	if err := validateMessage(message); err != nil {
		return "", err
	}
	encoded, _ := json.Marshal(encodedMessage{
		CreatedAt: message.CreatedAt.Format(time.RFC3339Nano),
		ID:        message.ID,
		Payload:   message.Payload,
	})
	return string(encoded), nil
}

// Decode validates a strict worker-message JSON object and returns its domain form.
func Decode(value string) (WorkerMessage, error) {
	decoder := json.NewDecoder(strings.NewReader(value))
	decoder.DisallowUnknownFields()
	var wire decodedMessage
	if err := decoder.Decode(&wire); err != nil {
		return WorkerMessage{}, messageError("worker message is not valid JSON", err)
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		cause := errors.New("worker message contains trailing JSON")
		return WorkerMessage{}, messageError("worker message must contain one JSON object", cause)
	}
	if wire.ID == nil || wire.CreatedAt == nil || wire.Payload == nil {
		cause := errors.New("worker message requires id, createdAt, and payload")
		return WorkerMessage{}, messageError("worker message fields are incomplete", cause)
	}
	createdAt, err := time.Parse(time.RFC3339Nano, *wire.CreatedAt)
	if err != nil {
		return WorkerMessage{}, messageError("worker message createdAt is not an RFC3339 instant", err)
	}
	message := WorkerMessage{ID: *wire.ID, CreatedAt: createdAt.UTC(), Payload: *wire.Payload}
	if err := validateMessage(message); err != nil {
		return WorkerMessage{}, err
	}
	return message, nil
}

func validateMessage(message WorkerMessage) error {
	if !validUUID(message.ID) {
		cause := fmt.Errorf("worker message id %q is not a canonical UUID", message.ID)
		return messageError("worker message id is invalid", cause)
	}
	if message.CreatedAt.IsZero() || message.CreatedAt.Year() < 0 || message.CreatedAt.Year() > 9999 {
		cause := errors.New("worker message createdAt is outside the RFC3339 range")
		return messageError("worker message createdAt is invalid", cause)
	}
	return nil
}

func validUUID(value string) bool {
	if len(value) != 36 || value[8] != '-' || value[13] != '-' || value[18] != '-' || value[23] != '-' {
		return false
	}
	compact := strings.ReplaceAll(value, "-", "")
	decoded, err := hex.DecodeString(compact)
	return err == nil && len(decoded) == 16
}

func messageError(detail string, cause error) error {
	problemType := problem.Type{
		ID: problemInvalidMessage, Title: "Invalid worker message", Version: problemVersion, Status: 400,
	}
	registry, _ := problem.NewRegistry(problem.LocalErrorPortal(), problemType)
	options := problem.DefaultTransformOptions()
	options.Registry = registry
	envelope := problem.FromObject(map[string]any{"problemId": problemType.ID}, options)
	envelope.Detail = &detail
	return problem.WrapError(envelope, cause)
}
