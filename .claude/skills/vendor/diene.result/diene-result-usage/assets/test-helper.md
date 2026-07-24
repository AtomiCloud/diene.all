# Variant assertions

The framework-free subpath returns matching payloads and throws a rich variant
diff on mismatches:

```ts
import { Err, None, Ok, Some } from '@atomicloud/diene.result';
import { expectErr, expectNone, expectOk, expectSome } from '@atomicloud/diene.result/test-helper';

const value = await expectOk(Ok<number, string>(2));
const error = await expectErr(Err<number, string>('bad'));
const some = await expectSome(Some(1));
await expectNone(None<number>());
```

Keep these assertions in consumer tests. TestHelper implementation coverage
belongs to the `meta` ledger, never the product unit ledger.
