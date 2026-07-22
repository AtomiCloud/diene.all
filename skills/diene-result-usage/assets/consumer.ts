import { Option, Result } from '@atomicloud/diene.result';

export const doubled = Result.ok<number, string>(21)
  .map(value => value * 2)
  .unwrap();

export const present = Option.fromNullable<string>('value').isSome;
