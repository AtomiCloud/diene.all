package sit_test

import (
	"context"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-consumer/lib/messagecodec"
	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	redis "github.com/redis/go-redis/v9"
)

func TestMessageJourney(t *testing.T) {
	harness := newSITHarness(t)
	id := newUUID(t)
	environment := workerEnvironment("message", id)
	ctx, cancel := context.WithTimeout(t.Context(), journeyTimeout)
	defer cancel()
	redisConnection := redisClient(t)
	payload, err := messagecodec.Encode(messagecodec.WorkerMessage{
		ID: id, CreatedAt: time.Now().UTC(), Payload: "journey",
	})
	if err != nil {
		t.Fatalf("encode worker message: %v", err)
	}
	if appendErr := redisConnection.XAdd(ctx, &redis.XAddArgs{
		Stream: environment["ATOMI_TRANSPORT__STREAM"],
		Values: map[string]any{"payload": payload},
	}).Err(); appendErr != nil {
		t.Fatalf("append worker message: %v", appendErr)
	}

	journey := e2e.Journey{
		Name: "message side effects",
		Steps: []e2e.Step{
			{
				Name:       "initialize persistence",
				Invocation: harness.invocation(nil, "db-init"),
				Expect:     e2e.Expectation{ExitCode: 0, StdoutContains: []string{`"ok":true`}},
			},
			{
				Name:       "consume the message",
				Invocation: harness.invocation(environment, "worker", "--once"),
				Expect: e2e.Expectation{
					ExitCode:       0,
					StdoutExcludes: []string{"message handling failed", "invalid worker message"},
				},
			},
		},
	}
	harness.run(t, journey)

	database := postgresClient(ctx, t)
	var objectKey string
	var storedPayload string
	if queryErr := database.QueryRow(
		ctx,
		"SELECT object_key, payload FROM processed_messages WHERE id = $1",
		id,
	).Scan(&objectKey, &storedPayload); queryErr != nil {
		t.Fatalf("read processed message: %v", queryErr)
	}
	if storedPayload != "journey" {
		t.Fatalf("processed payload = %q, want %q", storedPayload, "journey")
	}
	storage := storageClient(ctx, t)
	if _, headErr := storage.HeadObject(ctx, &s3.HeadObjectInput{
		Bucket: aws.String(requiredEnvironment(t, "SIT_STORAGE_BUCKET")),
		Key:    aws.String(objectKey),
	}); headErr != nil {
		t.Fatalf("find encrypted object %q: %v", objectKey, headErr)
	}
	pending, err := redisConnection.XPending(
		ctx,
		environment["ATOMI_TRANSPORT__STREAM"],
		environment["ATOMI_TRANSPORT__CONSUMER_GROUP"],
	).Result()
	if err != nil {
		t.Fatalf("read Redis pending count: %v", err)
	}
	if pending.Count != 0 {
		t.Fatalf("Redis pending count = %d, want 0", pending.Count)
	}
}
