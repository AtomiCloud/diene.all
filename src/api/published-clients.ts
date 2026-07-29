import {
  apiEngineConfigBlockSchema,
  createApiEngine,
  registerApiProblems,
  type ApiEngine,
  type BackendClientContext,
  type FetchLike,
} from '@atomicloud/diene.e2e/api';
import {
  ClientAuthStateRetriever,
  LogtoManagementClient,
  managementConfigFromAuthEngine,
  registerAuthProblems,
} from '@atomicloud/diene.e2e/auth';
import type { ProblemRegistry } from '@atomicloud/diene.e2e/problems';
import type { ApplicationConfig } from '../config/schema';

class ConfiguredBackendClient {
  constructor(readonly context: BackendClientContext) {}

  get(): Promise<Response> {
    return this.context.fetch(this.context.baseUrl);
  }
}

export interface PublishedClients {
  readonly api: ApiEngine;
  readonly auth: LogtoManagementClient;
}

export async function buildPublishedClients(
  config: ApplicationConfig,
  registry: ProblemRegistry,
  fetchImplementation: FetchLike = fetch,
): Promise<PublishedClients> {
  const authProblems = await registerAuthProblems(registry).match({
    err: problem => Promise.reject(new Error(problem.detail ?? problem.title)),
    ok: problems => problems,
  });
  const apiProblems = await registerApiProblems(registry).match({
    err: problem => Promise.reject(new Error(problem.detail ?? problem.title)),
    ok: problems => problems,
  });
  const retriever = new ClientAuthStateRetriever({ fetch: fetchImplementation });
  const bindings = config.api.backends.map(block =>
    apiEngineConfigBlockSchema.parse({
      ...block,
      auth: retriever,
      createClient: (context: BackendClientContext) => new ConfiguredBackendClient(context),
    }),
  );
  const api = await createApiEngine({ bindings, fetch: fetchImplementation, problems: apiProblems }).match({
    err: problem => Promise.reject(new Error(problem.detail ?? problem.title)),
    ok: engine => engine,
  });
  const auth = new LogtoManagementClient({
    config: managementConfigFromAuthEngine(config.auth),
    fetch: fetchImplementation,
    problems: authProblems,
  });
  return { api, auth };
}
