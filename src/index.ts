import {
  findNestedProblem as findNestedProblemValue,
  isProblem as isProblemValue,
  isProblemDetail as isProblemDetailValue,
  isResponse as isResponseValue,
  reconcileApiFailure as reconcileApiFailureValue,
  reconcileApiValue as reconcileApiValueValue,
  toResult as toResultValue,
} from './bridge';
import {
  apiEngineConfigBlockSchema as apiEngineConfigBlockSchemaValue,
  backendBaseUrlSchema as backendBaseUrlSchemaValue,
  createApiEngine as createApiEngineValue,
  DEFAULT_BACKEND_TIMEOUT_MS as DEFAULT_BACKEND_TIMEOUT_MS_VALUE,
  lpsmCoordinateSchema as lpsmCoordinateSchemaValue,
  OPAQUE_NETWORK_RETRY_ONCE as OPAQUE_NETWORK_RETRY_ONCE_VALUE,
} from './client-tree';
import { createBackendFetch as createBackendFetchValue } from './http-client';
import {
  API_PROBLEM_VERSION as API_PROBLEM_VERSION_VALUE,
  ApiAuthenticationFailure as ApiAuthenticationFailureValue,
  ApiBackendNotFound as ApiBackendNotFoundValue,
  ApiConfigurationFailure as ApiConfigurationFailureValue,
  ApiTransportFailure as ApiTransportFailureValue,
  ApiUpstreamFailure as ApiUpstreamFailureValue,
  createAuthenticationProblem as createAuthenticationProblemValue,
  createBackendNotFoundProblem as createBackendNotFoundProblemValue,
  createConfigurationProblem as createConfigurationProblemValue,
  createTransportProblem as createTransportProblemValue,
  createUpstreamProblem as createUpstreamProblemValue,
  registerApiProblems as registerApiProblemsValue,
} from './register';
import {
  createSwaggerAdapter as createSwaggerAdapterValue,
  proxyApiClient as proxyApiClientValue,
} from './swagger-adapter';

export const API_PROBLEM_VERSION = API_PROBLEM_VERSION_VALUE;
export const ApiAuthenticationFailure = ApiAuthenticationFailureValue;
export const ApiBackendNotFound = ApiBackendNotFoundValue;
export const ApiConfigurationFailure = ApiConfigurationFailureValue;
export const ApiTransportFailure = ApiTransportFailureValue;
export const ApiUpstreamFailure = ApiUpstreamFailureValue;
export const DEFAULT_BACKEND_TIMEOUT_MS = DEFAULT_BACKEND_TIMEOUT_MS_VALUE;
export const OPAQUE_NETWORK_RETRY_ONCE = OPAQUE_NETWORK_RETRY_ONCE_VALUE;
export const apiEngineConfigBlockSchema = apiEngineConfigBlockSchemaValue;
export const backendBaseUrlSchema = backendBaseUrlSchemaValue;
export const createApiEngine = createApiEngineValue;
export const createAuthenticationProblem = createAuthenticationProblemValue;
export const createBackendFetch = createBackendFetchValue;
export const createBackendNotFoundProblem = createBackendNotFoundProblemValue;
export const createConfigurationProblem = createConfigurationProblemValue;
export const createSwaggerAdapter = createSwaggerAdapterValue;
export const createTransportProblem = createTransportProblemValue;
export const createUpstreamProblem = createUpstreamProblemValue;
export const findNestedProblem = findNestedProblemValue;
export const isProblem = isProblemValue;
export const isProblemDetail = isProblemDetailValue;
export const isResponse = isResponseValue;
export const lpsmCoordinateSchema = lpsmCoordinateSchemaValue;
export const proxyApiClient = proxyApiClientValue;
export const reconcileApiFailure = reconcileApiFailureValue;
export const reconcileApiValue = reconcileApiValueValue;
export const registerApiProblems = registerApiProblemsValue;
export const toResult = toResultValue;
export type { IAuth } from './auth';
export type { Problem, ProblemDetail, ReconciliationContext, ReconciliationPhase, ToResultValue } from './bridge';
export type { ApiEngineConfigBlock, ResolvedApiEngineConfigBlock } from './client-tree';
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
} from './client-tree';
export type { BackendFetchOptions, FetchLike } from './http-client';
export type { ApiProblems } from './register';
