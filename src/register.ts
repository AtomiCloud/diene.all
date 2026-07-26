import {
  API_PROBLEM_VERSION as API_PROBLEM_VERSION_IMPLEMENTATION,
  ApiAuthenticationFailure as ApiAuthenticationFailureImplementation,
  ApiBackendNotFound as ApiBackendNotFoundImplementation,
  ApiConfigurationFailure as ApiConfigurationFailureImplementation,
  ApiTransportFailure as ApiTransportFailureImplementation,
  ApiUpstreamFailure as ApiUpstreamFailureImplementation,
  createAuthenticationProblem as createAuthenticationProblemImplementation,
  createBackendNotFoundProblem as createBackendNotFoundProblemImplementation,
  createConfigurationProblem as createConfigurationProblemImplementation,
  createTransportProblem as createTransportProblemImplementation,
  createUpstreamProblem as createUpstreamProblemImplementation,
  registerApiProblems as registerApiProblemsImplementation,
} from './lib/problems';

export const API_PROBLEM_VERSION = API_PROBLEM_VERSION_IMPLEMENTATION;
export const ApiAuthenticationFailure = ApiAuthenticationFailureImplementation;
export const ApiBackendNotFound = ApiBackendNotFoundImplementation;
export const ApiConfigurationFailure = ApiConfigurationFailureImplementation;
export const ApiTransportFailure = ApiTransportFailureImplementation;
export const ApiUpstreamFailure = ApiUpstreamFailureImplementation;
export const createAuthenticationProblem = createAuthenticationProblemImplementation;
export const createBackendNotFoundProblem = createBackendNotFoundProblemImplementation;
export const createConfigurationProblem = createConfigurationProblemImplementation;
export const createTransportProblem = createTransportProblemImplementation;
export const createUpstreamProblem = createUpstreamProblemImplementation;
export const registerApiProblems = registerApiProblemsImplementation;
export type { ApiProblems } from './lib/problems';
