// Package storage adapts the AWS SDK v2 S3 client to object-storage ports.
package storage

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net/url"
	"strings"

	"github.com/AtomiCloud/diene.go-consumer/adapters/tracing"
	"github.com/AtomiCloud/diene.go-consumer/lib/domain"
	"github.com/AtomiCloud/diene.go-standard-config/lib/standardconfig"
	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
	"github.com/aws/smithy-go"
)

// API is the AWS SDK v2 S3 surface used by Client.
type API interface {
	HeadBucket(context.Context, *s3.HeadBucketInput, ...func(*s3.Options)) (*s3.HeadBucketOutput, error)
	CreateBucket(context.Context, *s3.CreateBucketInput, ...func(*s3.Options)) (*s3.CreateBucketOutput, error)
	PutObject(context.Context, *s3.PutObjectInput, ...func(*s3.Options)) (*s3.PutObjectOutput, error)
	GetObject(context.Context, *s3.GetObjectInput, ...func(*s3.Options)) (*s3.GetObjectOutput, error)
	HeadObject(context.Context, *s3.HeadObjectInput, ...func(*s3.Options)) (*s3.HeadObjectOutput, error)
	DeleteObject(context.Context, *s3.DeleteObjectInput, ...func(*s3.Options)) (*s3.DeleteObjectOutput, error)
}

// Factory creates an S3-compatible API from one standard-config entry.
type Factory func(context.Context, standardconfig.StorageEntry) (API, error)

// Client is an instrumented S3-compatible object-storage client.
type Client struct {
	api    API
	bucket string
	region string
	tracer *tracing.Tracer
}

// Open constructs an AWS SDK v2 client for a standard-config storage entry.
func Open(ctx context.Context, entry standardconfig.StorageEntry, tracer *tracing.Tracer) (*Client, error) {
	return OpenWithFactory(ctx, entry, tracer, func(factoryCtx context.Context, configured standardconfig.StorageEntry) (API, error) {
		cfg, err := awsconfig.LoadDefaultConfig(
			factoryCtx,
			awsconfig.WithRegion(configured.Region),
			awsconfig.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(
				configured.AccessKeyID,
				configured.SecretAccessKey,
				"",
			)),
		)
		if err != nil {
			return nil, fmt.Errorf("storage: load AWS configuration: %w", err)
		}
		return s3.NewFromConfig(cfg, func(options *s3.Options) {
			options.BaseEndpoint = aws.String(configured.Endpoint)
			options.UsePathStyle = configured.ForcePathStyle
		}), nil
	})
}

// OpenWithFactory constructs an S3-compatible client through an injected factory.
func OpenWithFactory(
	ctx context.Context,
	entry standardconfig.StorageEntry,
	tracer *tracing.Tracer,
	factory Factory,
) (*Client, error) {
	if err := validateEntry(entry); err != nil {
		return nil, err
	}
	if tracer == nil {
		return nil, errors.New("storage: tracer is required")
	}
	if factory == nil {
		return nil, errors.New("storage: client factory is required")
	}
	api, err := factory(ctx, entry)
	if err != nil {
		return nil, fmt.Errorf("storage: open client: %w", err)
	}
	return New(api, entry.Bucket, entry.Region, tracer)
}

// New wraps an existing S3-compatible API.
func New(api API, bucket, region string, tracer *tracing.Tracer) (*Client, error) {
	if api == nil {
		return nil, errors.New("storage: API client is required")
	}
	if strings.TrimSpace(bucket) == "" {
		return nil, errors.New("storage: bucket is required")
	}
	if strings.TrimSpace(region) == "" {
		return nil, errors.New("storage: region is required")
	}
	if tracer == nil {
		return nil, errors.New("storage: tracer is required")
	}
	return &Client{api: api, bucket: bucket, region: region, tracer: tracer}, nil
}

// Ping checks whether the configured bucket is reachable.
func (c *Client) Ping(ctx context.Context) error {
	span, err := c.tracer.Start("storage.ping", c.attributes())
	if err != nil {
		return err
	}
	_, operationErr := c.api.HeadBucket(ctx, &s3.HeadBucketInput{Bucket: aws.String(c.bucket)})
	return span.End(operationErr)
}

// EnsureBucket creates the configured bucket only when it is absent.
func (c *Client) EnsureBucket(ctx context.Context) error {
	_, err := c.EnsureBucketCreated(ctx)
	return err
}

// EnsureBucketCreated ensures the bucket and reports whether it was created.
func (c *Client) EnsureBucketCreated(ctx context.Context) (bool, error) {
	span, err := c.tracer.Start("storage.ensure_bucket", c.attributes())
	if err != nil {
		return false, err
	}
	_, headErr := c.api.HeadBucket(ctx, &s3.HeadBucketInput{Bucket: aws.String(c.bucket)})
	if headErr == nil {
		return false, span.End(nil)
	}
	if !isNotFound(headErr) {
		return false, span.End(headErr)
	}
	input := &s3.CreateBucketInput{Bucket: aws.String(c.bucket)}
	if c.region != "us-east-1" {
		input.CreateBucketConfiguration = &types.CreateBucketConfiguration{
			LocationConstraint: types.BucketLocationConstraint(c.region),
		}
	}
	_, createErr := c.api.CreateBucket(ctx, input)
	if endErr := span.End(createErr); endErr != nil {
		return false, endErr
	}
	return true, nil
}

// Put stores content at key.
func (c *Client) Put(ctx context.Context, key string, content []byte, contentType string) error {
	if strings.TrimSpace(key) == "" {
		return errors.New("storage: object key is required")
	}
	span, err := c.tracer.Start("storage.put", c.objectAttributes(key))
	if err != nil {
		return err
	}
	input := &s3.PutObjectInput{
		Bucket: aws.String(c.bucket),
		Key:    aws.String(key),
		Body:   bytes.NewReader(content),
	}
	if strings.TrimSpace(contentType) != "" {
		input.ContentType = aws.String(contentType)
	}
	_, operationErr := c.api.PutObject(ctx, input)
	return span.End(operationErr)
}

// Save stores one encrypted domain blob and returns its provider-independent link.
func (c *Client) Save(ctx context.Context, input domain.SaveInput) (domain.StoredObject, error) {
	if err := c.Put(ctx, input.Key, []byte(input.Body), input.ContentType); err != nil {
		return domain.StoredObject{}, err
	}
	linkURL := url.URL{Scheme: "s3", Host: c.bucket, Path: input.Key}
	link := linkURL.String()
	return domain.StoredObject{Key: input.Key, Link: link}, nil
}

// Get reads key, distinguishing absence from an empty object.
func (c *Client) Get(ctx context.Context, key string) ([]byte, bool, error) {
	if strings.TrimSpace(key) == "" {
		return nil, false, errors.New("storage: object key is required")
	}
	span, err := c.tracer.Start("storage.get", c.objectAttributes(key))
	if err != nil {
		return nil, false, err
	}
	output, operationErr := c.api.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(c.bucket),
		Key:    aws.String(key),
	})
	if isNotFound(operationErr) {
		if endErr := span.End(nil); endErr != nil {
			return nil, false, endErr
		}
		return nil, false, nil
	}
	if operationErr != nil {
		return nil, false, span.End(operationErr)
	}
	if output == nil || output.Body == nil {
		bodyErr := errors.New("storage: get object returned no body")
		return nil, false, span.End(bodyErr)
	}
	content, readErr := io.ReadAll(output.Body)
	closeErr := output.Body.Close()
	operationErr = errors.Join(readErr, closeErr)
	if endErr := span.End(operationErr); endErr != nil {
		return nil, false, endErr
	}
	return content, true, nil
}

// Exists reports whether key exists.
func (c *Client) Exists(ctx context.Context, key string) (bool, error) {
	if strings.TrimSpace(key) == "" {
		return false, errors.New("storage: object key is required")
	}
	span, err := c.tracer.Start("storage.exists", c.objectAttributes(key))
	if err != nil {
		return false, err
	}
	_, operationErr := c.api.HeadObject(ctx, &s3.HeadObjectInput{
		Bucket: aws.String(c.bucket),
		Key:    aws.String(key),
	})
	if isNotFound(operationErr) {
		if endErr := span.End(nil); endErr != nil {
			return false, endErr
		}
		return false, nil
	}
	if endErr := span.End(operationErr); endErr != nil {
		return false, endErr
	}
	return true, nil
}

// Delete removes key. S3 deletion is idempotent for an absent key.
func (c *Client) Delete(ctx context.Context, key string) error {
	if strings.TrimSpace(key) == "" {
		return errors.New("storage: object key is required")
	}
	span, err := c.tracer.Start("storage.delete", c.objectAttributes(key))
	if err != nil {
		return err
	}
	_, operationErr := c.api.DeleteObject(ctx, &s3.DeleteObjectInput{
		Bucket: aws.String(c.bucket),
		Key:    aws.String(key),
	})
	return span.End(operationErr)
}

func (c *Client) attributes() map[string]any {
	return map[string]any{"db.system": "s3", "db.namespace": c.bucket}
}

func (c *Client) objectAttributes(key string) map[string]any {
	attributes := c.attributes()
	attributes["db.operation.parameter"] = key
	return attributes
}

func isNotFound(err error) bool {
	if err == nil {
		return false
	}
	var apiErr smithy.APIError
	if errors.As(err, &apiErr) {
		switch apiErr.ErrorCode() {
		case "NoSuchBucket", "NoSuchKey", "NotFound", "404":
			return true
		}
	}
	var statusErr interface{ HTTPStatusCode() int }
	return errors.As(err, &statusErr) && statusErr.HTTPStatusCode() == 404
}

func validateEntry(entry standardconfig.StorageEntry) error {
	parsed, parseErr := url.Parse(entry.Endpoint)
	switch {
	case parseErr != nil:
		return fmt.Errorf("storage: parse endpoint: %w", parseErr)
	case parsed.Scheme != "http" && parsed.Scheme != "https":
		return errors.New("storage: endpoint must use http or https")
	case parsed.Hostname() == "":
		return errors.New("storage: endpoint host is required")
	case strings.TrimSpace(entry.Region) == "":
		return errors.New("storage: region is required")
	case strings.TrimSpace(entry.Bucket) == "":
		return errors.New("storage: bucket is required")
	default:
		return nil
	}
}
