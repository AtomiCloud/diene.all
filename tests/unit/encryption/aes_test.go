package encryption_test

import (
	"bytes"
	"encoding/base64"
	"errors"
	"io"
	"testing"

	"github.com/AtomiCloud/diene.go-consumer/lib/encryption"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

func TestAES256GCMRoundTrip(t *testing.T) {
	t.Parallel()
	key := base64.StdEncoding.EncodeToString(make([]byte, 32))
	subject, err := encryption.NewAES256GCM(key, bytes.NewReader(make([]byte, 12)))
	if err != nil {
		t.Fatalf("construct encryptor: %v", err)
	}

	payload, err := subject.Encrypt("classified")
	if err != nil {
		t.Fatalf("encrypt: %v", err)
	}
	plaintext, err := subject.Decrypt(payload)
	if err != nil {
		t.Fatalf("decrypt: %v", err)
	}
	if plaintext != "classified" {
		t.Fatalf("plaintext = %q, want classified", plaintext)
	}
	if payload == plaintext {
		t.Fatal("encrypted payload unexpectedly equals plaintext")
	}
}

func TestAES256GCMUsesDefaultRandomSource(t *testing.T) {
	t.Parallel()
	key := base64.StdEncoding.EncodeToString(make([]byte, 32))
	subject, err := encryption.NewAES256GCM(key, nil)
	if err != nil {
		t.Fatalf("construct encryptor: %v", err)
	}
	if _, err := subject.Encrypt("payload"); err != nil {
		t.Fatalf("encrypt with default random source: %v", err)
	}
}

func TestAES256GCMRejectsInvalidKeys(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name string
		key  string
	}{
		{name: "invalid base64", key: "not-base64"},
		{name: "invalid AES size", key: base64.StdEncoding.EncodeToString([]byte("short"))},
		{name: "valid AES but not 256 bit", key: base64.StdEncoding.EncodeToString(make([]byte, 16))},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			_, err := encryption.NewAES256GCM(test.key, bytes.NewReader(make([]byte, 12)))
			assertProblem(t, err)
		})
	}
}

func TestAES256GCMReportsRandomFailure(t *testing.T) {
	t.Parallel()
	key := base64.StdEncoding.EncodeToString(make([]byte, 32))
	subject, err := encryption.NewAES256GCM(key, bytes.NewReader([]byte{1}))
	if err != nil {
		t.Fatalf("construct encryptor: %v", err)
	}
	_, err = subject.Encrypt("payload")
	assertProblem(t, err)
	if !errors.Is(err, io.ErrUnexpectedEOF) {
		t.Fatalf("error does not preserve random failure: %v", err)
	}
}

func TestAES256GCMRejectsMalformedEnvelopes(t *testing.T) {
	t.Parallel()
	key := base64.StdEncoding.EncodeToString(make([]byte, 32))
	subject, err := encryption.NewAES256GCM(key, bytes.NewReader(make([]byte, 12)))
	if err != nil {
		t.Fatalf("construct encryptor: %v", err)
	}
	tests := []struct {
		name    string
		payload string
	}{
		{name: "not JSON", payload: "not-json"},
		{name: "unknown field", payload: `{"ciphertext":"YQ==","iv":"YQ==","version":1,"extra":true}`},
		{name: "trailing JSON", payload: `{"ciphertext":"YQ==","iv":"YQ==","version":1}{}`},
		{name: "unsupported version", payload: `{"ciphertext":"YQ==","iv":"YQ==","version":2}`},
		{name: "blank field", payload: `{"ciphertext":"","iv":"YQ==","version":1}`},
		{name: "invalid nonce base64", payload: `{"ciphertext":"YQ==","iv":"!","version":1}`},
		{name: "invalid ciphertext base64", payload: `{"ciphertext":"!","iv":"AAAAAAAAAAAAAAAA","version":1}`},
		{name: "wrong nonce size", payload: `{"ciphertext":"YQ==","iv":"YQ==","version":1}`},
		{name: "authentication failure", payload: `{"ciphertext":"YQ==","iv":"AAAAAAAAAAAAAAAA","version":1}`},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			_, err := subject.Decrypt(test.payload)
			assertProblem(t, err)
		})
	}
}

func TestAES256GCMRejectsCiphertextFromAnotherKey(t *testing.T) {
	t.Parallel()
	firstKey := base64.StdEncoding.EncodeToString(make([]byte, 32))
	secondBytes := bytes.Repeat([]byte{1}, 32)
	secondKey := base64.StdEncoding.EncodeToString(secondBytes)
	first, err := encryption.NewAES256GCM(firstKey, bytes.NewReader(make([]byte, 12)))
	if err != nil {
		t.Fatalf("construct first encryptor: %v", err)
	}
	second, err := encryption.NewAES256GCM(secondKey, bytes.NewReader(make([]byte, 12)))
	if err != nil {
		t.Fatalf("construct second encryptor: %v", err)
	}
	payload, err := first.Encrypt("payload")
	if err != nil {
		t.Fatalf("encrypt: %v", err)
	}
	_, err = second.Decrypt(payload)
	assertProblem(t, err)
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
