import type { Problem } from '@atomicloud/diene.problems';
import { Err, Ok, type Result } from '@atomicloud/diene.result';
import type { TokenResponse } from '../lib/provider';
import type { CanonicalResourceKey, TokenCacheStore } from '../lib/resource-tree';

export class InMemoryTokenCacheStore implements TokenCacheStore {
  readonly #values = new Map<CanonicalResourceKey, TokenResponse>();
  #failure?: Problem;

  setFailure(problem?: Problem): void {
    this.#failure = problem;
  }

  get(key: CanonicalResourceKey): Result<TokenResponse | undefined, Problem> {
    return this.#failure === undefined ? Ok(this.#values.get(key)) : Err(this.#failure);
  }

  set(key: CanonicalResourceKey, value: TokenResponse): Result<void, Problem> {
    if (this.#failure !== undefined) return Err(this.#failure);
    this.#values.set(key, value);
    return Ok(undefined);
  }

  delete(key: CanonicalResourceKey): Result<void, Problem> {
    if (this.#failure !== undefined) return Err(this.#failure);
    this.#values.delete(key);
    return Ok(undefined);
  }

  clear(): Result<void, Problem> {
    if (this.#failure !== undefined) return Err(this.#failure);
    this.#values.clear();
    return Ok(undefined);
  }

  inspect(key: CanonicalResourceKey): TokenResponse | undefined {
    return this.#values.get(key);
  }
}
