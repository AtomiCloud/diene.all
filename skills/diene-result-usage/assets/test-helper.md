# Using the /test-helper subpath

The `@atomicloud/diene.result/test-helper` subpath ships dependency-light,
assert-the-asserter helpers so a downstream suite can pin a variant and receive
its payload, with a clear `TestHelperFailure` diff on mismatch. It imports no
test framework, so it works under any runner.

```ts
import { beErr, beNone, beOk, beSome } from '@atomicloud/diene.result/test-helper';
import { Option, Result } from '@atomicloud/diene.result';

const value = beOk(Result.ok<number, string>(2)); // returns 2
const error = beErr(Result.err<string, number>('bad')); // returns 'bad'
const some = beSome(Option.some(1)); // returns 1
beNone(Option.none<number>()); // returns void
```

Each helper throws `TestHelperFailure` when the asserted variant is absent, with
a message naming the offending variant and its payload (for example
`Expected Ok, got Err carrying bad.`). Keep helper coverage out of the unit
ledger and prove framework-specific fakes in the meta tier.
