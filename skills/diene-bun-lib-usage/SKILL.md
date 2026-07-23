---
name: diene-bun-lib-usage
description: Use when consuming @atomicloud/diene.bun-lib — importing its API, choosing ESM vs CJS, or deciding whether this library needs a TestHelper.
---

`@atomicloud/diene.bun-lib` ships dual **ESM + CJS** with bundled types. Import
from the package root; both `import` and `require` resolve, and TypeScript picks
up `.d.ts` (ESM) or `.d.cts` (CJS) automatically.

- **ESM**: `import { buildSampleKey, createRedisStore, persistSample } from '@atomicloud/diene.bun-lib';`
- **CJS**: `const { buildSampleKey } = require('@atomicloud/diene.bun-lib');`

Read [patterns.md](patterns.md) for the do's, don'ts, and — because this
library ships no TestHelper — how to create one for it when a real consumer need
appears.
