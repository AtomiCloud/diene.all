import {
  ProblemCatalog,
  createGenericProblemRegistry,
  emitProblemResource,
  type ErrorPortalConfig,
  type ProblemResource,
  type ProblemResourceIdentity,
} from '@atomicloud/diene.e2e/problems';
import { z } from 'zod';

const MessageHandlerFailed = Object.freeze({
  dataSchema: z.object({ messageId: z.string().min(1), stage: z.string().min(1) }).strict(),
  id: 'message_handler_failed',
  status: 500,
  title: 'Message handler failed',
  version: 'v1',
});

export interface DomainProblems {
  readonly catalog: ProblemCatalog;
  readonly registry: ReturnType<typeof createGenericProblemRegistry>;
}

export function createDomainProblems(portal: ErrorPortalConfig, stream: string, version: string): DomainProblems {
  const registry = createGenericProblemRegistry(portal, version);
  const definition = registry.register({ ...MessageHandlerFailed, version });
  const catalog = new ProblemCatalog(registry);
  catalog.declare(definition, {
    endpoints: [{ method: 'CONSUME', path: `/streams/${stream}` }],
    recoverable: true,
  });
  return { catalog, registry };
}

export function emitDomainProblemResource(
  portal: ErrorPortalConfig,
  stream: string,
  identity: ProblemResourceIdentity,
): ProblemResource {
  return emitProblemResource(createDomainProblems(portal, stream, identity.version).catalog, identity);
}
