import { Err, None, Ok, type Option, type Result } from '@atomicloud/diene.result';
import { expectErr, expectNone, expectOk } from '@atomicloud/diene.result/test-helper';

async function resolveThroughRequireTypes(): Promise<void> {
  const result: Result<number, string> = Ok<number, string>(42);
  const failure: Result<number, string> = Err<number, string>('typed-cjs');
  const option: Option<number> = None<number>();

  const value: number = await expectOk(result);
  const error: string = await expectErr(failure);
  await expectNone(option);

  void [value, error];
}

void resolveThroughRequireTypes;
