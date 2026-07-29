# @atomicloud/diene.core-utils — patterns

## Keys and Result handling

```ts
import { namespacedKey, slugify } from '@atomicloud/diene.core-utils';

const slug = slugify('Customer Profile'); // customer-profile

const key = await namespacedKey('Customer Profile', 'Primary Email').match({
  ok: value => value,
  err: error => {
    throw new Error(`invalid cache key: ${error.message}`);
  },
});
// customer-profile:primary-email
```

Do not assume a key is valid and immediately `unwrap()` it. Treat an empty
normalized namespace or key as ordinary validation and choose a caller-appropriate
`err` branch.

## Bounded work and deterministic values

```ts
import {
  fuzzyIncludes,
  isRecord,
  mapWithConcurrency,
  sha256,
  stableConfig,
  unique,
} from '@atomicloud/diene.core-utils';

const matches = fuzzyIncludes('Release Candidate', 'candidate');
const names = ['a', 'a', 'b'].filter(unique);

const config = { retries: 3, features: { audit: true } };
const digest = await sha256(JSON.stringify(stableConfig(config)));

const records = values.filter(isRecord);
const outputs = await mapWithConcurrency(inputs, 4, async input => process(input));
```

Use a concurrency limit that matches the API, database, or filesystem capacity;
do not make all work concurrent by default. `stableConfig` makes configuration
comparison and digest input repeatable, but does not validate a configuration
schema. `fuzzyIncludes` is deliberately only case-insensitive substring matching.

## Explicit-root paths

```ts
import { safeJoin } from '@atomicloud/diene.core-utils';

const uploadRoot = '/srv/app/uploads';
const destination = safeJoin(uploadRoot, tenantId, `${documentId}.json`);
```

Pass the root that the caller owns. Do not resolve relative paths from
`process.cwd()`, and do not bypass `safeJoin` with unchecked user-provided path
segments.

## C0 Temporal codecs

```ts
import { Temporal } from '@js-temporal/polyfill';
import {
  formatWireDate,
  formatWireDateTime,
  formatWireDuration,
  formatWireTime,
  formatWireTimeZone,
  parseWireDate,
  parseWireDateTime,
  parseWireDuration,
  parseWireTime,
  parseWireTimeZone,
} from '@atomicloud/diene.core-utils';

const date = formatWireDate(Temporal.PlainDate.from('2026-07-24'));
const time = formatWireTime(Temporal.PlainTime.from('09:30:00'));
const instant = formatWireDateTime(Temporal.Instant.from('2026-07-24T09:30:00Z'));
const duration = formatWireDuration(Temporal.Duration.from('PT15M'));
const zone = formatWireTimeZone(parseWireTimeZone('Europe/London'));

parseWireDate(date);
parseWireTime(time);
parseWireDateTime(instant);
parseWireDuration(duration);
```

The only accepted transport spellings are date `YYYY-MM-DD`, time `HH:mm:ss`, a
UTC RFC3339 instant ending in `Z` (with canonical fractional seconds when
needed), an ISO8601 duration, and a canonical IANA timezone identifier. Do not
put localized dates, offsets, or timezone abbreviations such as `PST` on the
wire.

## TestHelper: only when evidence changes the verdict

This package ships no TestHelper because consumers call deterministic value
functions directly, rooted filesystem helpers use real temporary directories,
and stock equality covers their outputs. Do not create a separate helper package
or another skill.

Re-open the decision only when a real consumer-facing seam must be faked (for
example, a newly added injectable clock) or the same nontrivial assertion appears
repeatedly across consumer suites. If that happens, add a dependency-light
`@atomicloud/diene.core-utils/test-helper` subpath in this package, keep test
framework dependencies out of runtime helper code, and extend this same skill.
Its meta tier must prove assert-the-asserter behavior, contract parity between
fakes and their real counterpart, and fixture/builder invariants. Activate the
`meta` Codecov upload only once that helper and its meta tests exist; until then
`pls test:meta` stays an inherited no-op and uploads no empty `meta` flag.
