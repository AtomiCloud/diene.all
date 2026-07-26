package seedrecord

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"strings"

	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

const (
	problemVersion            = "v1"
	problemInvalidSeedRecords = "invalid-seed-records"
)

// Record is one idempotently inserted seed value.
type Record struct {
	ID    string
	Value string
}

type wireRecord struct {
	ID    *string `json:"id"`
	Value *string `json:"value"`
}

// Parse decodes and validates a strict JSON array of seed records.
func Parse(value []byte) ([]Record, error) {
	decoder := json.NewDecoder(bytes.NewReader(value))
	decoder.DisallowUnknownFields()
	var wire []wireRecord
	if err := decoder.Decode(&wire); err != nil {
		return nil, seedError("seed data is not a valid JSON array", err)
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		cause := errors.New("seed data contains trailing JSON")
		return nil, seedError("seed data must contain one JSON array", cause)
	}
	if wire == nil {
		cause := errors.New("seed data must be an array")
		return nil, seedError("seed data must not be null", cause)
	}
	records := make([]Record, 0, len(wire))
	for _, candidate := range wire {
		if candidate.ID == nil || candidate.Value == nil || strings.TrimSpace(*candidate.ID) == "" {
			cause := errors.New("each seed record requires a non-blank id and a value")
			return nil, seedError("seed record is invalid", cause)
		}
		records = append(records, Record{ID: strings.TrimSpace(*candidate.ID), Value: *candidate.Value})
	}
	return records, nil
}

// SelectMissing preserves input order while selecting records not already present.
func SelectMissing(records []Record, existingIDs map[string]struct{}) []Record {
	missing := make([]Record, 0, len(records))
	for _, record := range records {
		if _, exists := existingIDs[record.ID]; !exists {
			missing = append(missing, record)
		}
	}
	return missing
}

func seedError(detail string, cause error) error {
	problemType := problem.Type{
		ID: problemInvalidSeedRecords, Title: "Invalid seed records", Version: problemVersion, Status: 400,
	}
	registry, _ := problem.NewRegistry(problem.LocalErrorPortal(), problemType)
	options := problem.DefaultTransformOptions()
	options.Registry = registry
	envelope := problem.FromObject(map[string]any{"problemId": problemType.ID}, options)
	envelope.Detail = &detail
	return problem.WrapError(envelope, cause)
}
