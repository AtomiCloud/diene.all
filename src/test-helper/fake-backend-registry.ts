import type { Problem } from '@atomicloud/diene.problems';
import { Err, Ok, type Result } from '@atomicloud/diene.result';
import type { BackendRegistration, BackendRegistry } from '../lib/resource-tree';

export class InMemoryBackendRegistry implements BackendRegistry {
  readonly values = new Map<string, BackendRegistration>();
  failure?: Problem;

  register(registration: BackendRegistration): Result<void, Problem> {
    if (this.failure !== undefined) return Err(this.failure);
    this.values.set(registration.backendId, registration);
    return Ok(undefined);
  }

  get(backendId: string): BackendRegistration | undefined {
    return this.values.get(backendId);
  }

  list(): readonly BackendRegistration[] {
    return [...this.values.values()];
  }
}
