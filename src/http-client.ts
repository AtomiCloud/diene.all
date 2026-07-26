import { createBackendFetch as createBackendFetchImplementation } from './lib/backend-fetch';

export const createBackendFetch = createBackendFetchImplementation;
export type { BackendFetchOptions } from './lib/backend-fetch';
export type { FetchLike } from './lib/types';
