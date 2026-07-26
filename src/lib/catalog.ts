import { slugify } from '@atomicloud/diene.core-utils';
import { z } from 'zod';
import { problemDataJsonSchema } from './publish.js';
import { ProblemRegistry, ProblemRegistryError } from './registry.js';
import type {
  ErrorPortalConfig,
  ProblemCatalogDeclaration,
  ProblemCatalogEntry,
  ProblemEndpoint,
  ProblemResource,
  ProblemResourceIdentity,
  RegisteredProblem,
} from './types.js';

const endpointMethodPattern = /^[A-Z]+$/;

function validateEndpoints(endpoints: readonly ProblemEndpoint[]): readonly ProblemEndpoint[] {
  return endpoints.map(endpoint => {
    if (!endpointMethodPattern.test(endpoint.method)) {
      throw new RangeError(`Problem endpoint method must be uppercase; received ${endpoint.method}`);
    }
    if (!endpoint.path.startsWith('/')) {
      throw new RangeError(`Problem endpoint path must start with '/'; received ${endpoint.path}`);
    }
    return Object.freeze({ ...endpoint });
  });
}

export class ProblemCatalog {
  readonly #entries = new Map<string, ProblemCatalogEntry>();

  constructor(readonly registry: ProblemRegistry) {}

  declare(problem: RegisteredProblem, declaration: ProblemCatalogDeclaration): ProblemCatalogEntry {
    const registered = this.registry.get(problem.id, problem.version);
    if (registered?.type !== problem.type) {
      throw new ProblemRegistryError('unknown', `Problem ${problem.id} does not belong to this catalog registry`);
    }
    if (this.#entries.has(problem.id)) {
      throw new ProblemRegistryError('duplicate', `Problem ${problem.id} is already declared in the catalog`);
    }

    const entry: ProblemCatalogEntry = Object.freeze({
      id: registered.id,
      type: registered.type,
      title: registered.title,
      status: registered.status,
      recoverable: declaration.recoverable,
      data: problemDataJsonSchema(registered),
      endpoints: validateEndpoints(declaration.endpoints),
    });
    this.#entries.set(entry.id, entry);
    return entry;
  }

  list(): readonly ProblemCatalogEntry[] {
    return [...this.#entries.values()].sort((left, right) => left.id.localeCompare(right.id));
  }
}

function assertResourceIdentity(catalog: ProblemCatalog, identity: ProblemResourceIdentity): void {
  const { portal } = catalog.registry;
  for (const [name, expected, actual] of [
    ['platform', portal.platform, identity.platform],
    ['service', portal.service, identity.service],
    ['landscape', portal.landscape, identity.landscape],
  ] as const) {
    if (expected !== actual) {
      throw new RangeError(`Problem resource ${name} ${actual} does not match registry ErrorPortal value ${expected}`);
    }
  }

  const versions = new Set(
    catalog.list().map(entry => catalog.registry.list().find(problem => problem.type === entry.type)?.version),
  );
  if (versions.size !== 1 || !versions.has(identity.version)) {
    throw new RangeError(`Problem resource version ${identity.version} must match every catalog entry`);
  }
}

export function emitProblemResource(catalog: ProblemCatalog, identity: ProblemResourceIdentity): ProblemResource {
  assertResourceIdentity(catalog, identity);
  const name = [identity.service, identity.landscape, identity.version].map(slugify).join('-');

  return {
    apiVersion: 'atomi.cloud/v1alpha1',
    kind: 'Problem',
    metadata: {
      name,
      namespace: identity.platform,
    },
    spec: {
      platform: identity.platform,
      service: identity.service,
      landscape: identity.landscape,
      version: identity.version,
      problems: catalog.list().map(entry => ({
        id: entry.id,
        type: entry.type,
        title: entry.title,
        status: entry.status,
        recoverable: entry.recoverable,
        schema: entry.data,
        endpoints: entry.endpoints,
      })),
    },
  };
}

export const ValidationError = Object.freeze({
  id: 'validation_error',
  title: 'Validation Error',
  status: 400,
  dataSchema: z
    .object({
      issues: z.array(
        z.object({
          path: z.array(z.string()),
          message: z.string(),
          code: z.string().optional(),
        }),
      ),
    })
    .strict(),
});

export const EntityNotFound = Object.freeze({
  id: 'entity_not_found',
  title: 'Entity Not Found',
  status: 404,
  dataSchema: z.object({ entityType: z.string(), id: z.string() }).strict(),
});

export const Unauthorized = Object.freeze({
  id: 'unauthorized',
  title: 'Unauthorized',
  status: 401,
  dataSchema: z.object({ reason: z.string().optional() }).strict(),
});

export function registerGenericProblems(registry: ProblemRegistry, version = 'v1') {
  return Object.freeze({
    ValidationError: registry.register({ ...ValidationError, version }),
    EntityNotFound: registry.register({ ...EntityNotFound, version }),
    Unauthorized: registry.register({ ...Unauthorized, version }),
  });
}

export function createGenericProblemRegistry(portal: ErrorPortalConfig, version = 'v1'): ProblemRegistry {
  const registry = new ProblemRegistry(portal);
  registerGenericProblems(registry, version);
  return registry;
}
