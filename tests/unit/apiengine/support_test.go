package apiengine_test

import (
	"errors"
	"io"
	"net/http"
	"time"
)

// brokenBodyDoer answers with a response whose body fails on read, which is the
// connection that dies mid-stream — distinct from one that never connected.
type brokenBodyDoer struct{}

func (brokenBodyDoer) Do(*http.Request) (*http.Response, error) {
	return &http.Response{
		StatusCode: http.StatusOK,
		Header:     http.Header{},
		Body:       io.NopCloser(brokenReader{}),
	}, nil
}

type brokenReader struct{}

func (brokenReader) Read([]byte) (int, error) {
	return 0, errors.New("connection reset while reading the body")
}

// slowDoer blocks until the request context expires, so a per-backend timeout
// is observable without a real slow server.
type slowDoer struct{}

func (slowDoer) Do(request *http.Request) (*http.Response, error) {
	select {
	case <-request.Context().Done():
		return nil, request.Context().Err()
	case <-time.After(time.Minute):
		return nil, errors.New("slowDoer was not cancelled")
	}
}

// failingDoer always fails the round trip with a fixed error.
type failingDoer struct{ err error }

func (d failingDoer) Do(*http.Request) (*http.Response, error) {
	return nil, d.err
}

// countingDoer records how many round trips were attempted.
type countingDoer struct {
	attempts int
	err      error
}

func (d *countingDoer) Do(*http.Request) (*http.Response, error) {
	d.attempts++
	return nil, d.err
}
