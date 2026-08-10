# Ubiquitous language: StandardConfig

The shipped surface lives in `Lib`; the demo consumer that composes it lives in
`App`; the container glue and fakes consumers test against live in `TestHelper`.

| Term            | Meaning                                                                                          |
| --------------- | ------------------------------------------------------------------------------------------------ |
| Preset          | One infra config block this library ships: postgres, cache, kv, or storage. Schema, not loader.  |
| Block           | A preset's resolved value: a keyed map of named connections, bound as `PostgresBlock` and kin.   |
| Entry           | One named connection inside a block — the host, port, credentials, and sizing of one endpoint.   |
| Connection name | The UPPERCASE key an entry sits under (`MAIN`, `REPLICA`, `SESSIONS`). R14 calls it a pool name. |
| Authored name   | The connection name as written in YAML or an environment variable, before the canonical rule.    |
| Bound name      | The same name after the config lib folds casing and strips separators. `MAIN` arrives as `main`. |
| Cache           | The EPHEMERAL Redis-protocol preset. RAM-backed; losing it must never lose durable state.        |
| Kv              | The PERSISTENT Redis-protocol preset. Same wire protocol as cache, opposite durability contract. |
| Block storage   | The three-member object surface: save an object, get its link, get a signed URL. Nothing more.   |
| Path style      | S3 addressing that puts the bucket in the path. True for MinIO, false for virtual-hosted hosts.  |
| Start helper    | A TestHelper call that boots a real dependency AND emits the schema-valid block reaching it.     |
| Contract parity | One behavioural suite run against both the real adapter and the fake, so the fake cannot drift.  |

Say "preset", "block", "entry", and "connection name" consistently.

A preset is never a single connection — it is always a map — because the whole
point of the shape is that a second instance is data. Do not say "the postgres
config"; say "the postgres block" or "the `MAIN` entry".

Keep **cache** and **kv** apart in speech as well as in code. They are two
presets over one connection shape, and the only difference is the one that
matters: cache may vanish, kv may not. Calling either "the Redis config" invites
exactly the substitution the two-preset split exists to prevent.

Avoid "loader", "merger", or "validator" for anything here. This library
contributes schemas; `AtomiCloud.Diene.Config` is the sole merger and validator,
and blurring that boundary is how a second config engine gets built by accident.
Likewise avoid "otel preset" or "auth preset" — engine blocks are engine-owned
and service-composed (C0 §3), and they are not presets.
