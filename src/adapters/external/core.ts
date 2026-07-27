import type { BackendBinding, BackendClientContext } from '@atomicloud/diene.api-engine';
import type { IAuthStateRetriever } from '@atomicloud/diene.auth-engine';
import type { RootConfig } from '@/adapters/server-config';

/**
 * THE per-backend registration point (kept from argon by name and role).
 *
 * Adding a backend to this template is exactly two edits:
 *  1. a `backends.<name>` entry in config (baseUrl + LPSM coordinate), and
 *  2. a generated-client factory in the tree below.
 *
 * Everything else — auth header wiring, Result<T, Problem> mapping, per-backend
 * onboarding gates — flows from these bindings through the api-engine.
 */

/**
 * Generated-client factories keyed by backend name. The sample ships a plain
 * JSON client; a real service replaces entries with its generated
 * swagger-typescript-api clients (`createClient` receives the backend's policy
 * fetch, so the SDK maps to Result<T, Problem> automatically).
 */
const clientFactories: Record<string, (context: BackendClientContext) => object> = {};

const defaultJsonClient = (context: BackendClientContext) => ({
  request: async (path: string, init?: RequestInit) => context.fetch(new URL(path, context.baseUrl), init),
});

/** Build the immutable api-engine binding list from config + auth retriever. */
export const backendBindings = (
  config: RootConfig,
  landscape: string,
  auth: IAuthStateRetriever,
): readonly BackendBinding[] =>
  Object.entries(config.get('backends')).map(([name, backend]) => ({
    coordinate: {
      landscape,
      platform: backend.platform,
      service: backend.service,
      module: backend.module,
    },
    baseUrl: backend.baseUrl,
    resource: {
      platform: backend.platform,
      landscape,
      service: backend.service,
      resourceName: name,
    },
    auth,
    createClient: clientFactories[name] ?? defaultJsonClient,
    retry: 'opaque-network-once',
  }));
