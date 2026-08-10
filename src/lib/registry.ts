import { Err, Ok, type Result } from '@atomicloud/diene.result';
import type { z } from 'zod';
import type { ErrorPortalConfig, Problem, ProblemDefinition, ProblemInit, RegisteredProblem } from './types.js';
import { buildProblemTypeUri } from './uri.js';

export class ProblemRegistryError extends Error {
  constructor(
    readonly code: 'duplicate' | 'invalid' | 'unknown',
    message: string,
    options?: ErrorOptions,
  ) {
    super(message, options);
    this.name = 'ProblemRegistryError';
  }
}

function bindProblem<TSchema extends z.ZodType>(
  portal: ErrorPortalConfig,
  definition: ProblemDefinition<TSchema>,
): RegisteredProblem<TSchema> {
  if (!Number.isInteger(definition.status) || definition.status < 100 || definition.status > 599) {
    throw new ProblemRegistryError(
      'invalid',
      `Problem status must be an integer from 100 through 599; received ${definition.status}`,
    );
  }
  if (definition.title.trim() === '') {
    throw new ProblemRegistryError('invalid', 'Problem title must not be empty');
  }

  try {
    return Object.freeze({
      ...definition,
      type: buildProblemTypeUri(portal, definition.version, definition.id),
    });
  } catch (error: unknown) {
    throw new ProblemRegistryError('invalid', `Invalid problem definition ${definition.id}`, { cause: error });
  }
}

export function createProblem<TSchema extends z.ZodType>(
  definition: RegisteredProblem<TSchema>,
  init: ProblemInit<z.input<TSchema>>,
): Problem<z.output<TSchema>> {
  const parsed = definition.dataSchema.parse(init.data);
  const status = init.status ?? definition.status;
  if (!Number.isInteger(status) || status < 100 || status > 599) {
    throw new ProblemRegistryError(
      'invalid',
      `Problem status override must be an integer from 100 through 599; received ${status}`,
    );
  }
  return {
    type: definition.type,
    title: definition.title,
    status,
    ...(init.detail === undefined ? {} : { detail: init.detail }),
    ...(init.instance === undefined ? {} : { instance: init.instance }),
    data: parsed,
  };
}

export class ProblemRegistry {
  readonly portal: ErrorPortalConfig;
  readonly #entries = new Map<string, RegisteredProblem>();

  constructor(portal: ErrorPortalConfig) {
    this.portal = Object.freeze({ ...portal });
  }

  register<TSchema extends z.ZodType>(definition: ProblemDefinition<TSchema>): RegisteredProblem<TSchema> {
    const key = this.#key(definition.id, definition.version);
    if (this.#entries.has(key)) {
      throw new ProblemRegistryError(
        'duplicate',
        `Problem id ${definition.id} is already registered for version ${definition.version}`,
      );
    }
    const registered = bindProblem(this.portal, definition);
    this.#entries.set(key, registered);
    return registered;
  }

  tryRegister<TSchema extends z.ZodType>(
    definition: ProblemDefinition<TSchema>,
  ): Result<RegisteredProblem<TSchema>, ProblemRegistryError> {
    try {
      return Ok(this.register(definition));
    } catch (error: unknown) {
      return Err(error as ProblemRegistryError);
    }
  }

  get(id: string, version?: string): RegisteredProblem | undefined {
    if (version !== undefined) {
      return this.#entries.get(this.#key(id, version));
    }

    const matches = [...this.#entries.values()].filter(entry => entry.id === id);
    if (matches.length > 1) {
      throw new ProblemRegistryError('invalid', `Problem id ${id} is ambiguous without a version`);
    }
    return matches[0];
  }

  require(id: string, version?: string): RegisteredProblem {
    const entry = this.get(id, version);
    if (entry === undefined) {
      const suffix = version === undefined ? '' : ` for version ${version}`;
      throw new ProblemRegistryError('unknown', `Problem id ${id} is not registered${suffix}`);
    }
    return entry;
  }

  list(): readonly RegisteredProblem[] {
    return [...this.#entries.values()].sort((left, right) =>
      left.version === right.version ? left.id.localeCompare(right.id) : left.version.localeCompare(right.version),
    );
  }

  #key(id: string, version: string): string {
    return `${version}:${id}`;
  }
}
