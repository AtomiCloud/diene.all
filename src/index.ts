import { createBackendFetch as createBackendFetchValue } from './lib/backend-fetch';
import { createApiEngine as createApiEngineValue } from './lib/engine';
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
} from './lib/problems';
import {
  findNestedProblem as findNestedProblemValue,
  reconcileApiFailure as reconcileApiFailureValue,
  reconcileApiValue as reconcileApiValueValue,
} from './lib/reconcile';

export const API_PROBLEM_VERSION = API_PROBLEM_VERSION_VALUE;
export const ApiAuthenticationFailure = ApiAuthenticationFailureValue;
export const ApiBackendNotFound = ApiBackendNotFoundValue;
export const ApiConfigurationFailure = ApiConfigurationFailureValue;
export const ApiTransportFailure = ApiTransportFailureValue;
export const ApiUpstreamFailure = ApiUpstreamFailureValue;
export const createApiEngine = createApiEngineValue;
export const createAuthenticationProblem = createAuthenticationProblemValue;
export const createBackendFetch = createBackendFetchValue;
export const createBackendNotFoundProblem = createBackendNotFoundProblemValue;
export const createConfigurationProblem = createConfigurationProblemValue;
export const createTransportProblem = createTransportProblemValue;
export const createUpstreamProblem = createUpstreamProblemValue;
export const findNestedProblem = findNestedProblemValue;
export const reconcileApiFailure = reconcileApiFailureValue;
export const reconcileApiValue = reconcileApiValueValue;
export const registerApiProblems = registerApiProblemsValue;
export type { BackendFetchOptions } from './lib/backend-fetch';
export type { ApiProblems } from './lib/problems';
export type {
  ApiClient,
  ApiEngine,
  ApiEngineOptions,
  ApiMethod,
  BackendBinding,
  BackendClientContext,
  FetchLike,
  LpsmCoordinate,
  LpsmKey,
  ReconciliationContext,
  ReconciliationPhase,
  RescueTrip,
  RescueTripContext,
  ResolvedBackend,
} from './lib/types';
