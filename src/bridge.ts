import { isProblem as isProblemImplementation, type Problem, type ProblemDetail } from '@atomicloud/diene.problems';
import { Res, type Result, type ResultSerial } from '@atomicloud/diene.result';

import {
  findNestedProblem as findNestedProblemImplementation,
  reconcileApiFailure as reconcileApiFailureImplementation,
  reconcileApiValue as reconcileApiValueImplementation,
} from './lib/reconcile';
import type { ReconciliationContext } from './lib/types';

export type ToResultValue<TValue> =
  Awaited<TValue> extends Result<infer TInner, unknown>
    ? TInner
    : Awaited<TValue> extends Response
      ? unknown
      : Awaited<TValue>;

/** Problem recognition stays owned by and delegated to diene.problems. */
export const isProblem: (value: unknown) => value is Problem = isProblemImplementation;
/** ProblemDetail is the dependency's compatibility alias for Problem. */
export const isProblemDetail: (value: unknown) => value is ProblemDetail = isProblemImplementation;

export function isResponse(value: unknown): value is Response {
  return value instanceof Response;
}

/** Reconcile SDK values, Results, Responses, and failures without a rejected public promise. */
export function toResult<TValue>(
  value: TValue,
  context: ReconciliationContext,
): Result<ToResultValue<TValue>, Problem> {
  const serial = reconcileApiValueImplementation(value, context) as Promise<
    ResultSerial<ToResultValue<TValue>, Problem>
  >;
  return Res.fromSerial(serial);
}

export const findNestedProblem = findNestedProblemImplementation;
export const reconcileApiFailure = reconcileApiFailureImplementation;
export const reconcileApiValue = reconcileApiValueImplementation;
export type { Problem, ProblemDetail };
export type { ReconciliationContext, ReconciliationPhase } from './lib/types';
