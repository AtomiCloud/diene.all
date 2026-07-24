import { Ok, Opt } from '@atomicloud/diene.result';

export async function consumeResult(): Promise<{ doubled: number; present: boolean }> {
  const doubled = await Ok<number, string>(21)
    .map(value => value * 2)
    .unwrap();
  const present = await Opt.fromNative('value').isSome();
  return { doubled, present };
}
