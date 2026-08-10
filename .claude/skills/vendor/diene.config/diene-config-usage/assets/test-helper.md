# Faking config in tests

Import `@atomicloud/diene.config/test-helper` — never mutate `process.env` or
write real files in a unit test.

```ts
import { InMemoryConfigSource, stubConfig, withLandscape, expectInvalid } from '@atomicloud/diene.config/test-helper';
import { ConfigRegistry } from '@atomicloud/diene.config';
import { z } from 'zod';

const registry = ConfigRegistry.create().register('server', z.object({ port: z.number(), host: z.string() }));

// A validated config from plain-object tiers (always passes the registry):
const config = await stubConfig(registry, { base: { server: { port: 80, host: 'h' } } });

// Assert a bad tier set fails final-layer validation:
const error = await expectInvalid(registry, { base: { server: { port: 'x', host: 'h' } } });

// A landscape fake stamps app.landscape so the loader selects the overlay:
const source = withLandscape('prod', { base: { server: { port: 80, host: 'h' } } });
```

## Real-vs-fake contract parity

Run ONE behavioral suite against both `YamlConfigSource` (real files + env) and
`InMemoryConfigSource` (plain objects) and assert identical `config.all()`. The
fake feeds the SAME loader as production, so parity is guaranteed by construction.
