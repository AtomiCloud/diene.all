import { describe, it } from 'bun:test';
import should from 'should';
import { z } from 'zod';
import { consumerDriver, devConfig, initialize, waitFor } from './driver';

const metricsResponseSchema = z.object({ data: z.object({ result: z.array(z.unknown()) }) });

describe('OTel export SIT', () => {
  it('should export worker health metrics and adapter traces through Alloy', async () => {
    // Arrange
    const driver = consumerDriver();
    should((await initialize(driver)).code).equal(0);
    const id = crypto.randomUUID();
    const consumerName = `otel-${id}`;
    const stream = `sit.otel.${id}`;

    // Act
    const worker = await driver.run(['worker', '--once'], {
      ATOMI_HEALTH__HEARTBEAT_FILE: `dist/run/otel-${id}.json`,
      ATOMI_TRANSPORT__CONSUMER_GROUP: `sit-${id}`,
      ATOMI_TRANSPORT__CONSUMER_NAME: consumerName,
      ATOMI_TRANSPORT__STREAM: stream,
    });
    let metricCount = 0;
    let traceRows = 0;
    await waitFor(async () => {
      const metricQuery = `atomi_worker_health{atomi_consumer_name="${consumerName}",atomi_transport_stream="${stream}",atomi_worker_state="healthy"}`;
      const metrics = metricsResponseSchema.parse(
        await fetch(`${devConfig.victoriaMetrics.endpoint}/api/v1/query?query=${encodeURIComponent(metricQuery)}`).then(
          response => response.json(),
        ),
      );
      metricCount = metrics.data.result.length;
      const query = encodeURIComponent(
        `SELECT count() FROM otel.otel_traces WHERE SpanAttributes['messaging.destination.name'] = '${stream}'`,
      );
      traceRows = Number(
        await fetch(`${devConfig.clickhouse.endpoint}/?query=${query}`).then(response => response.text()),
      );
      return metricCount > 0 && traceRows > 0;
    }, 45_000);

    // Assert
    should(worker.code).equal(0);
    should(metricCount).be.above(0);
    should(traceRows).be.above(0);
  }, 60_000);
});
