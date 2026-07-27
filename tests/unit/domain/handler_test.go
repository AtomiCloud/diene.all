package domain_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-consumer/lib/domain"
	"github.com/AtomiCloud/diene.go-consumer/lib/messagecodec"
	"github.com/AtomiCloud/diene.go-errors-problems/lib/problem"
)

type fakeEncryptor struct {
	value string
	err   error
}

func (fake fakeEncryptor) Encrypt(string) (string, error) {
	return fake.value, fake.err
}

func (fakeEncryptor) Decrypt(string) (string, error) {
	return "", nil
}

type fakeStorage struct {
	inputs []domain.SaveInput
	err    error
}

func (fake *fakeStorage) Save(_ context.Context, input domain.SaveInput) (domain.StoredObject, error) {
	fake.inputs = append(fake.inputs, input)
	return domain.StoredObject{Key: input.Key, Link: "memory://" + input.Key}, fake.err
}

type fakeRepository struct {
	records  []domain.ProcessedMessageRecord
	inserted bool
	err      error
}

func (fake *fakeRepository) Insert(_ context.Context, record domain.ProcessedMessageRecord) (bool, error) {
	fake.records = append(fake.records, record)
	return fake.inserted, fake.err
}

func TestSampleWorkerHandlerSuccess(t *testing.T) {
	t.Parallel()
	repository := &fakeRepository{inserted: true}
	storage := &fakeStorage{}
	subject, err := domain.NewSampleWorkerHandler(handlerProblems(t), repository, storage, fakeEncryptor{value: "encrypted"}, " processed ")
	if err != nil {
		t.Fatalf("construct handler: %v", err)
	}
	createdAt := time.Date(2026, time.July, 25, 14, 30, 0, 0, time.FixedZone("SGT", 8*60*60))

	actual, err := subject.Handle(context.Background(), messagecodec.WorkerMessage{
		ID: "11d8ab19-cdc7-4bc4-a178-70a352c352e8", CreatedAt: createdAt, Payload: "hello",
	})
	if err != nil {
		t.Fatalf("handle: %v", err)
	}
	wantKey := "processed/11d8ab19-cdc7-4bc4-a178-70a352c352e8.json.enc"
	if !actual.Inserted || actual.ObjectKey != wantKey {
		t.Fatalf("result = %#v", actual)
	}
	if len(storage.inputs) != 1 || storage.inputs[0] != (domain.SaveInput{
		Body: "encrypted", ContentType: "application/octet-stream", Key: wantKey,
	}) {
		t.Fatalf("storage inputs = %#v", storage.inputs)
	}
	if len(repository.records) != 1 || repository.records[0].ObjectKey != wantKey ||
		repository.records[0].Payload != "hello" || repository.records[0].CreatedAt.Location() != time.UTC {
		t.Fatalf("repository records = %#v", repository.records)
	}
}

func TestSampleWorkerHandlerReportsDuplicate(t *testing.T) {
	t.Parallel()
	subject, err := domain.NewSampleWorkerHandler(
		handlerProblems(t), &fakeRepository{inserted: false}, &fakeStorage{}, fakeEncryptor{value: "encrypted"}, "processed",
	)
	if err != nil {
		t.Fatalf("construct handler: %v", err)
	}
	actual, err := subject.Handle(context.Background(), sampleMessage())
	if err != nil {
		t.Fatalf("handle: %v", err)
	}
	if actual.Inserted {
		t.Fatal("duplicate message unexpectedly reported an insert")
	}
}

func TestSampleWorkerHandlerValidatesConstructor(t *testing.T) {
	t.Parallel()
	repository := &fakeRepository{}
	storage := &fakeStorage{}
	encryptor := fakeEncryptor{}
	tests := []struct {
		name       string
		repository domain.MessageRepository
		storage    domain.EncryptedBlobStorage
		encryptor  fakeEncryptor
		prefix     string
	}{
		{name: "repository", storage: storage, encryptor: encryptor, prefix: "processed"},
		{name: "storage", repository: repository, encryptor: encryptor, prefix: "processed"},
		{name: "encryptor", repository: repository, storage: storage, prefix: "processed"},
		{name: "prefix", repository: repository, storage: storage, encryptor: encryptor, prefix: " "},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			var injectedEncryptor interface {
				Encrypt(string) (string, error)
				Decrypt(string) (string, error)
			}
			if test.name != "encryptor" {
				injectedEncryptor = test.encryptor
			}
			_, err := domain.NewSampleWorkerHandler(handlerProblems(t), test.repository, test.storage, injectedEncryptor, test.prefix)
			assertProblem(t, err)
		})
	}
}

func TestSampleWorkerHandlerMapsStageFailures(t *testing.T) {
	t.Parallel()
	sentinel := errors.New("dependency unavailable")
	tests := []struct {
		name       string
		repository *fakeRepository
		storage    *fakeStorage
		encryptor  fakeEncryptor
		wantStores int
		wantWrites int
	}{
		{name: "encryption", repository: &fakeRepository{}, storage: &fakeStorage{}, encryptor: fakeEncryptor{err: sentinel}},
		{name: "storage", repository: &fakeRepository{}, storage: &fakeStorage{err: sentinel}, encryptor: fakeEncryptor{value: "encrypted"}, wantStores: 1},
		{name: "persistence", repository: &fakeRepository{err: sentinel}, storage: &fakeStorage{}, encryptor: fakeEncryptor{value: "encrypted"}, wantStores: 1, wantWrites: 1},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			subject, err := domain.NewSampleWorkerHandler(handlerProblems(t), test.repository, test.storage, test.encryptor, "processed")
			if err != nil {
				t.Fatalf("construct handler: %v", err)
			}
			_, err = subject.Handle(context.Background(), sampleMessage())
			assertProblem(t, err)
			if !errors.Is(err, sentinel) {
				t.Fatalf("error does not preserve cause: %v", err)
			}
			if len(test.storage.inputs) != test.wantStores || len(test.repository.records) != test.wantWrites {
				t.Fatalf("calls = storage %d, repository %d", len(test.storage.inputs), len(test.repository.records))
			}
		})
	}
}

func sampleMessage() messagecodec.WorkerMessage {
	return messagecodec.WorkerMessage{
		ID:        "11d8ab19-cdc7-4bc4-a178-70a352c352e8",
		CreatedAt: time.Date(2026, time.July, 25, 6, 30, 0, 0, time.UTC),
		Payload:   "hello",
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

// handlerProblems builds the domain catalog the handler raises failures through.
func handlerProblems(t *testing.T) *domain.Problems {
	t.Helper()
	problems, err := domain.NewProblems(samplePortal(), "consumer.messages", "v1")
	if err != nil {
		t.Fatalf("new problems: %v", err)
	}
	return problems
}

func TestNewSampleWorkerHandlerRejectsNilProblems(t *testing.T) {
	t.Parallel()
	_, err := domain.NewSampleWorkerHandler(
		nil, &fakeRepository{}, &fakeStorage{}, fakeEncryptor{value: "encrypted"}, "processed",
	)
	assertProblem(t, err)
}
