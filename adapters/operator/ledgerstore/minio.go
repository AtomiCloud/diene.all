// Package ledgerstore implements the pure lib ledger.Store port against an
// S3-compatible object store (MinIO in the int tier, mirroring the future R2
// bucket). Entries are JSON objects keyed by their coordinate under a
// per-controller prefix; the store never holds secret values, only the pointers
// the pure ledger records.
package ledgerstore

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"

	"github.com/minio/minio-go/v7"

	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/ledger"
)

// ErrBucketMissing means the bootstrap-owned durable-ledger bucket is absent.
// The operator never creates or manages this bucket itself.
var ErrBucketMissing = errors.New("ledgerstore: bootstrap-provisioned bucket is missing")

// MinioStore is an S3/MinIO-backed ledger.Store.
type MinioStore struct {
	client *minio.Client
	bucket string
	prefix string
}

// NewMinioStore wraps an existing S3/MinIO client as a ledger.Store rooted at a
// per-controller object prefix. The client is constructed by the composition
// root so this constructor stays a pure wrapper.
func NewMinioStore(client *minio.Client, bucket, prefix string) *MinioStore {
	return &MinioStore{client: client, bucket: bucket, prefix: prefix}
}

// VerifyBucket verifies that bootstrap provisioned the ledger bucket. An absent
// bucket is a loud startup failure; this adapter never creates or manages it.
func (s *MinioStore) VerifyBucket(ctx context.Context) error {
	exists, err := s.client.BucketExists(ctx, s.bucket)
	if err != nil {
		return err
	}
	if !exists {
		return fmt.Errorf("%w: %q; provision it during L0 bootstrap", ErrBucketMissing, s.bucket)
	}
	return nil
}

// EnsureBucket is retained temporarily for deprecated composition-root
// compatibility. It delegates to VerifyBucket and never creates.
func (s *MinioStore) EnsureBucket(ctx context.Context) error {
	return s.VerifyBucket(ctx)
}

func (s *MinioStore) objectName(key string) string {
	return s.prefix + key
}

// Get reads a ledger entry. A missing object reports found=false, not an error.
func (s *MinioStore) Get(ctx context.Context, key string) (ledger.Entry, bool, error) {
	obj, err := s.client.GetObject(ctx, s.bucket, s.objectName(key), minio.GetObjectOptions{})
	if err != nil {
		return ledger.Entry{}, false, err
	}
	defer func() { _ = obj.Close() }()

	data, err := io.ReadAll(obj)
	if err != nil {
		if minio.ToErrorResponse(err).Code == "NoSuchKey" {
			return ledger.Entry{}, false, nil
		}
		return ledger.Entry{}, false, err
	}

	var entry ledger.Entry
	if err := json.Unmarshal(data, &entry); err != nil {
		return ledger.Entry{}, false, err
	}
	return entry, true, nil
}

// Put writes a ledger entry as a JSON object.
func (s *MinioStore) Put(ctx context.Context, entry ledger.Entry) error {
	data, err := json.Marshal(entry)
	if err != nil {
		return err
	}
	_, err = s.client.PutObject(
		ctx, s.bucket, s.objectName(entry.Coordinate.Key()),
		bytes.NewReader(data), int64(len(data)),
		minio.PutObjectOptions{ContentType: "application/json"},
	)
	return err
}

// Purge physically removes one ledger object. It is intentionally outside the
// ordinary ledger.Store interface and is wired only into a permit-checking
// Decommission service.
func (s *MinioStore) Purge(ctx context.Context, key string) error {
	return s.client.RemoveObject(ctx, s.bucket, s.objectName(key), minio.RemoveObjectOptions{})
}
