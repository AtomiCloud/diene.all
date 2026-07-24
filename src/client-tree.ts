import {
  apiEngineConfigBlockSchema as apiEngineConfigBlockSchemaImplementation,
  backendBaseUrlSchema as backendBaseUrlSchemaImplementation,
  DEFAULT_BACKEND_TIMEOUT_MS as DEFAULT_BACKEND_TIMEOUT_MS_IMPLEMENTATION,
  lpsmCoordinateSchema as lpsmCoordinateSchemaImplementation,
  OPAQUE_NETWORK_RETRY_ONCE as OPAQUE_NETWORK_RETRY_ONCE_IMPLEMENTATION,
} from './lib/config';
import { createApiEngine as createApiEngineImplementation } from './lib/engine';

export const apiEngineConfigBlockSchema = apiEngineConfigBlockSchemaImplementation;
export const backendBaseUrlSchema = backendBaseUrlSchemaImplementation;
export const DEFAULT_BACKEND_TIMEOUT_MS = DEFAULT_BACKEND_TIMEOUT_MS_IMPLEMENTATION;
export const lpsmCoordinateSchema = lpsmCoordinateSchemaImplementation;
export const OPAQUE_NETWORK_RETRY_ONCE = OPAQUE_NETWORK_RETRY_ONCE_IMPLEMENTATION;
export const createApiEngine = createApiEngineImplementation;

export type { ApiEngineConfigBlock, ResolvedApiEngineConfigBlock } from './lib/config';
export type {
  ApiClient,
  ApiEngine,
  ApiEngineOptions,
  ApiMethod,
  BackendBinding,
  BackendClientContext,
  LpsmCoordinate,
  LpsmKey,
  RescueTrip,
  RescueTripContext,
  ResolvedBackend,
  RetryProfile,
} from './lib/types';
