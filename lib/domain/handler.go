package domain

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/AtomiCloud/diene.go-consumer/lib/encryption"
	"github.com/AtomiCloud/diene.go-consumer/lib/messagecodec"
)

// ProcessedMessageRecord is the durable result of handling one worker message.
type ProcessedMessageRecord struct {
	ID        string
	ObjectKey string
	Payload   string
	CreatedAt time.Time
}

// SaveInput is an encrypted object-storage write.
type SaveInput struct {
	Body        string
	ContentType string
	Key         string
}

// StoredObject identifies an object accepted by storage.
type StoredObject struct {
	Key  string
	Link string
}

// MessageRepository persists processed-message records idempotently.
type MessageRepository interface {
	Insert(ctx context.Context, record ProcessedMessageRecord) (bool, error)
}

// EncryptedBlobStorage stores the encrypted payload side effect.
type EncryptedBlobStorage interface {
	Save(ctx context.Context, input SaveInput) (StoredObject, error)
}

// HandledMessage is the observable result of one handler invocation.
type HandledMessage struct {
	Inserted  bool
	ObjectKey string
}

// SampleWorkerHandler is the fenced go-consumer sample domain handler.
type SampleWorkerHandler struct {
	repository MessageRepository
	storage    EncryptedBlobStorage
	encryptor  encryption.Encryptor
	blobPrefix string
}

// NewSampleWorkerHandler validates and constructs the sample domain handler.
func NewSampleWorkerHandler(
	repository MessageRepository,
	storage EncryptedBlobStorage,
	encryptor encryption.Encryptor,
	blobPrefix string,
) (*SampleWorkerHandler, error) {
	if repository == nil {
		return nil, raiseLocalHandler("constructor", "construction", "message repository is required", errors.New("nil message repository"))
	}
	if storage == nil {
		return nil, raiseLocalHandler("constructor", "construction", "encrypted blob storage is required", errors.New("nil encrypted blob storage"))
	}
	if encryptor == nil {
		return nil, raiseLocalHandler("constructor", "construction", "encryptor is required", errors.New("nil encryptor"))
	}
	prefix := strings.TrimSpace(blobPrefix)
	if prefix == "" {
		return nil, raiseLocalHandler("constructor", "construction", "blob prefix is required", errors.New("blank blob prefix"))
	}
	return &SampleWorkerHandler{
		repository: repository,
		storage:    storage,
		encryptor:  encryptor,
		blobPrefix: prefix,
	}, nil
}

// Handle encrypts, stores, and then idempotently persists one worker message.
func (handler *SampleWorkerHandler) Handle(
	ctx context.Context,
	message messagecodec.WorkerMessage,
) (HandledMessage, error) {
	objectKey := handler.blobPrefix + "/" + message.ID + ".json.enc"
	encrypted, err := handler.encryptor.Encrypt(message.Payload)
	if err != nil {
		return HandledMessage{}, raiseLocalHandler(message.ID, "encryption", "message encryption failed", err)
	}
	_, err = handler.storage.Save(ctx, SaveInput{
		Body: encrypted, ContentType: "application/octet-stream", Key: objectKey,
	})
	if err != nil {
		return HandledMessage{}, raiseLocalHandler(message.ID, "storage", "message storage failed", err)
	}
	inserted, err := handler.repository.Insert(ctx, ProcessedMessageRecord{
		ID: message.ID, ObjectKey: objectKey, Payload: message.Payload, CreatedAt: message.CreatedAt.UTC(),
	})
	if err != nil {
		return HandledMessage{}, raiseLocalHandler(message.ID, "persistence", "message persistence failed", err)
	}
	return HandledMessage{Inserted: inserted, ObjectKey: objectKey}, nil
}
