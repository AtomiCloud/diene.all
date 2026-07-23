import {
  Err,
  Ok,
  Res,
  Some,
  type Option,
  type Result,
  type ResultSerial,
} from '@atomicloud/diene.result';
import { expectErr, expectOk, expectSome } from '@atomicloud/diene.result/test-helper';

const result: Result<number, string> = Ok<number, string>(42);
const failure: Result<number, string> = Err<number, string>('typed');
const option: Option<string> = Some('node16-esm');
const wire: ResultSerial<number, string> = await result.serial();
const hydrated: Result<number, string> = Res.fromSerial<number, string>(wire);

const value: number = await expectOk(hydrated);
const error: string = await expectErr(failure);
const some: string = await expectSome(option);

void [value, error, some];
