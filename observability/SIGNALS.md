# Signal contract

| Signal                                 | Type      | Meaning                                       |
| -------------------------------------- | --------- | --------------------------------------------- |
| `mercury_intake_total`                 | counter   | Registered provider requests by outcome       |
| `mercury_verification_failures_total`  | counter   | Requests rejected before persistence          |
| `mercury_dedup_hits_total`             | counter   | Landscape-local 72h SETNX hits                |
| `mercury_events_persisted_total`       | counter   | Events durably written before acknowledgement |
| `mercury_delivery_attempts_total`      | counter   | Endpoint attempts by outcome                  |
| `mercury_delivery_failures_total`      | counter   | Failed endpoint attempts                      |
| `mercury_delivery_lag_seconds`         | histogram | Receive-to-success latency                    |
| `mercury_delivery_queue_depth`         | gauge     | Pending and due retry work                    |
| `mercury_dlq_depth`                    | gauge     | Replayable exhausted obligations              |
| `mercury_stale_map_total`              | counter   | 421 responses that trigger one recompile      |
| `mercury_quota_breaches_total`         | counter   | In-app 429 decisions                          |
| `mercury_archive_success_total`        | counter   | Archived month streams                        |
| `mercury_archive_failures_total`       | counter   | Failed archives that block deletion           |
| `mercury_circuit_open`                 | gauge     | Endpoint circuit state                        |
| `mercury_apple_backfill_missed_cycles` | gauge     | Consecutive Apple backfill cycles missed      |

Logs include `event`, `tenant_id`, `route_id`, `endpoint_id`, `landscape`,
`provider`, `event_id`, and trace context. Raw bodies, provider credentials,
delivery-signing keys, and secret pointers are never logged.
