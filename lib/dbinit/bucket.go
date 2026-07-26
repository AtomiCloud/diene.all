package dbinit

import (
	"context"
	"fmt"
	"strings"
)

// BucketProvisioner ensures one configured bucket exists.
type BucketProvisioner interface {
	EnsureBucket(ctx context.Context) error
}

// NamedBucket associates a storage connection name with its provisioner.
type NamedBucket struct {
	Name        string
	Provisioner BucketProvisioner
}

// BucketCreator conditionally creates the configured buckets.
type BucketCreator struct {
	enabled bool
	buckets []NamedBucket
}

// NewBucketCreator creates the flag-controlled bucket phase.
func NewBucketCreator(enabled bool, buckets []NamedBucket) (*BucketCreator, error) {
	for index, bucket := range buckets {
		if strings.TrimSpace(bucket.Name) == "" {
			return nil, fmt.Errorf("dbinit: bucket %d has no name", index)
		}
		if bucket.Provisioner == nil {
			return nil, fmt.Errorf("dbinit: bucket provisioner %q is required", bucket.Name)
		}
	}
	return &BucketCreator{enabled: enabled, buckets: append([]NamedBucket(nil), buckets...)}, nil
}

// Run ensures every bucket when creation is enabled.
func (b *BucketCreator) Run(ctx context.Context) error {
	if !b.enabled {
		return nil
	}
	for _, bucket := range b.buckets {
		if err := bucket.Provisioner.EnsureBucket(ctx); err != nil {
			return fmt.Errorf("dbinit: ensure bucket %q: %w", bucket.Name, err)
		}
	}
	return nil
}
