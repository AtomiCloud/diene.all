import { proxyApiClient as proxyApiClientImplementation } from './lib/proxy';

export const proxyApiClient = proxyApiClientImplementation;
export const createSwaggerAdapter = proxyApiClientImplementation;
