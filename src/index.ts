import {
  DEFAULT_HANDOFF_MOUNT as deferredDefaultHandoffMount,
  initiateHandoff as runDeferredHandoff,
} from './lib/deferred/initiator';

export const DEFAULT_HANDOFF_MOUNT = deferredDefaultHandoffMount;
export const initiateHandoff: typeof runDeferredHandoff = deps => runDeferredHandoff(deps);

export {
  type FetchLike as LogtoManagementFetchLike,
  LogtoManagementClient,
  type LogtoManagementConfig,
  type LogtoManagementDeps,
  managementConfigFromAuthEngine,
} from './adapters/logto/management';
export * from './adapters/logto/provider';
export * from './adapters/redis-deferred-store';
export * from './lib/cache';
export * from './lib/config';
export * from './lib/deferred/carrier';
export * from './lib/deferred/exchange';
export type {
  FetchLike as HandoffFetchLike,
  InitiateHandoffDeps,
  InitiateHandoffResult,
} from './lib/deferred/initiator';
export * from './lib/deferred/mint';
export {
  type Clock,
  type DeferredNonceRecord,
  type DeferredTokenStore,
  type NonceState,
  systemClock as deferredSystemClock,
} from './lib/deferred/store';
export * from './lib/jwt';
export * from './lib/onboard/pre-onboarding';
export * from './lib/onboard/sync';
export * from './lib/problems';
export * from './lib/provider';
export * from './lib/redirect/return-to';
export * from './lib/resource-tree';
export * from './lib/retriever';
export * from './lib/retrievers/client';
export * from './lib/retrievers/server';
