package sit_test

import (
	"context"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-consumer/lib/messagecodec"
	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
	redis "github.com/redis/go-redis/v9"
)

func TestEnvOverrideJourney(t *testing.T) {
	harness := newSITHarness(t)
	id := newUUID(t)
	environment := workerEnvironment("override", id)
	ctx, cancel := context.WithTimeout(t.Context(), journeyTimeout)
	defer cancel()
	redisConnection := redisClient(t)
	payload, err := messagecodec.Encode(messagecodec.WorkerMessage{
		ID: id, CreatedAt: time.Now().UTC(), Payload: "override",
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
		Name: "environment override",
		Steps: []e2e.Step{
			{
				Name:       "initialize persistence",
				Invocation: harness.invocation(nil, "db-init"),
				Expect:     e2e.Expectation{ExitCode: 0, StdoutContains: []string{`"ok":true`}},
			},
			{
				Name:       "consume with overridden transport identity",
				Invocation: harness.invocation(environment, "worker", "--once"),
				Expect: e2e.Expectation{
					ExitCode:       0,
					StdoutExcludes: []string{"message handling failed", "invalid worker message"},
				},
			},
		},
	}
	harness.run(t, journey)

	consumers, err := redisConnection.XInfoConsumers(
		ctx,
		environment["ATOMI_TRANSPORT__STREAM"],
		environment["ATOMI_TRANSPORT__CONSUMER_GROUP"],
	).Result()
	if err != nil {
		t.Fatalf("read Redis consumer information: %v", err)
	}
	for _, consumer := range consumers {
		if consumer.Name == environment["ATOMI_TRANSPORT__CONSUMER_NAME"] {
			return
		}
	}
	t.Fatalf(
		"overridden consumer %q is absent from Redis consumer information: %#v",
		environment["ATOMI_TRANSPORT__CONSUMER_NAME"],
		consumers,
	)
}
