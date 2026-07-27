package sit_test

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/AtomiCloud/diene.go-consumer/lib/messagecodec"
	"github.com/AtomiCloud/diene.go-e2e/lib/e2e"
	redis "github.com/redis/go-redis/v9"
)

func TestOtelExportJourney(t *testing.T) {
	harness := newSITHarness(t)
	id := newUUID(t)
	environment := workerEnvironment("otel", id)
	ctx, cancel := context.WithTimeout(t.Context(), journeyTimeout)
	defer cancel()
	redisConnection := redisClient(t)
	payload, err := messagecodec.Encode(messagecodec.WorkerMessage{
		ID: id, CreatedAt: time.Now().UTC(), Payload: "telemetry",
	})
	if err != nil {
		t.Fatalf("encode telemetry worker message: %v", err)
	}
	if appendErr := redisConnection.XAdd(ctx, &redis.XAddArgs{
		Stream: environment["ATOMI_TRANSPORT__STREAM"],
		Values: map[string]any{"payload": payload},
	}).Err(); appendErr != nil {
		t.Fatalf("append telemetry worker message: %v", appendErr)
	}
	journey := e2e.Journey{
		Name: "OpenTelemetry export",
		Steps: []e2e.Step{
			{
				Name:       "initialize instrumented adapters",
				Invocation: harness.invocation(nil, "db-init"),
				Expect:     e2e.Expectation{ExitCode: 0, StdoutContains: []string{`"ok":true`}},
			},
			{
				Name:       "emit worker telemetry",
				Invocation: harness.invocation(environment, "worker", "--once"),
				Expect: e2e.Expectation{
					ExitCode:       0,
					StdoutExcludes: []string{"export failed", "message handling failed"},
				},
			},
		},
	}
	harness.run(t, journey)

	consumer := environment["ATOMI_TRANSPORT__CONSUMER_NAME"]
	stream := environment["ATOMI_TRANSPORT__STREAM"]
	metricQuery := fmt.Sprintf(
		`atomi_worker_health{atomi_consumer_name=%q,atomi_transport_stream=%q,atomi_worker_state="healthy"}`,
		consumer,
		stream,
	)
	traceQuery := fmt.Sprintf(
		"SELECT count() FROM otel.otel_traces WHERE SpanAttributes['messaging.destination.name'] = '%s'",
		sqlLiteral(stream),
	)
	logQuery := fmt.Sprintf(
		"SELECT count() FROM otel.otel_logs WHERE Body = 'message handled' AND LogAttributes['messageId'] = '%s'",
		sqlLiteral(id),
	)
	var metricCount int
	var traceCount int64
	var logCount int64
	pollCtx, pollCancel := context.WithTimeout(t.Context(), 45*time.Second)
	defer pollCancel()
	err = waitFor(pollCtx, 250*time.Millisecond, func(checkCtx context.Context) (bool, error) {
		var metricErr error
		metricCount, metricErr = victoriaMetricCount(
			checkCtx,
			requiredEnvironment(t, "SIT_VICTORIA_METRICS_ENDPOINT"),
			metricQuery,
		)
		var traceErr error
		traceCount, traceErr = clickHouseCount(
			checkCtx,
			requiredEnvironment(t, "SIT_CLICKHOUSE_ENDPOINT"),
			traceQuery,
		)
		var logErr error
		logCount, logErr = clickHouseCount(
			checkCtx,
			requiredEnvironment(t, "SIT_CLICKHOUSE_ENDPOINT"),
			logQuery,
		)
		return metricCount > 0 && traceCount > 0 && logCount > 0, errors.Join(metricErr, traceErr, logErr)
	})
	if err != nil {
		t.Fatalf(
			"telemetry did not arrive: metrics=%d traces=%d logs=%d: %v",
			metricCount,
			traceCount,
			logCount,
			err,
		)
	}
}
