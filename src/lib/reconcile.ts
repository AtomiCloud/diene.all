import { isRecord } from '@atomicloud/diene.core-utils';
import { isProblem, type Problem } from '@atomicloud/diene.problems';
import type { ResultSerial } from '@atomicloud/diene.result';

import { createTransportProblem, createUpstreamProblem } from './problems';
import type { ReconciliationContext } from './types';

interface ResultLike {
  serial(): Promise<ResultSerial<unknown, unknown>>;
}

function isResultLike(value: unknown): value is ResultLike {
  return isRecord(value) && typeof value.serial === 'function';
}

function isPromiseLike(value: unknown): value is PromiseLike<unknown> {
  return (
    (typeof value === 'object' || typeof value === 'function') &&
    value !== null &&
    typeof (value as { readonly then?: unknown }).then === 'function'
  );
}

function errorDetail(error: unknown): string {
  if (error instanceof Error && error.message !== '') return error.message;
  if (isRecord(error)) {
    if (typeof error.detail === 'string' && error.detail !== '') return error.detail;
    if (typeof error.message === 'string' && error.message !== '') return error.message;
  }
  if (typeof error === 'string' && error !== '') return error;
  return 'The API invocation failed before a usable response was received.';
}

/** Find an RFC 9457 Problem anywhere in a Kiota-style nested error without looping. */
export function findNestedProblem(value: unknown): Problem | undefined {
  const pending: unknown[] = [value];
  const visited = new Set<object>();
  while (pending.length > 0) {
    const current = pending.shift();
    if (isProblem(current)) return current;
    if (!isRecord(current) || visited.has(current)) continue;
    visited.add(current);
    for (const child of Object.values(current)) {
      if ((typeof child === 'object' && child !== null) || typeof child === 'function') {
        pending.push(child);
      }
    }
  }
  return undefined;
}

function receivedStatus(value: unknown): number | undefined {
  if (value instanceof Response) return value.status;
  if (!isRecord(value)) return undefined;
  for (const field of ['status', 'statusCode', 'responseStatusCode'] as const) {
    const candidate = value[field];
    if (typeof candidate === 'number' && Number.isInteger(candidate) && candidate >= 100 && candidate <= 599) {
      return candidate;
    }
  }
  if (value.response instanceof Response) return value.response.status;
  return undefined;
}

function nestedResponse(value: unknown): Response | undefined {
  if (value instanceof Response) return value;
  if (!isRecord(value)) return undefined;
  return value.response instanceof Response ? value.response : undefined;
}

function nestedJsonBody(value: unknown): unknown {
  if (!isRecord(value)) return undefined;
  for (const field of ['responseBody', 'body', 'additionalData'] as const) {
    const candidate = value[field];
    if (isRecord(candidate) || Array.isArray(candidate)) return candidate;
  }
  return undefined;
}

function isJson(response: Response): boolean {
  const contentType = response.headers.get('content-type')?.toLowerCase() ?? '';
  return contentType.includes('/json') || contentType.includes('+json');
}

async function readText(response: Response, context: ReconciliationContext): Promise<ResultSerial<string, Problem>> {
  try {
    return ['ok', await response.text()];
  } catch (error) {
    return [
      'err',
      createTransportProblem(
        context.problems,
        context.backendKey,
        `Response body could not be read: ${errorDetail(error)}`,
      ),
    ];
  }
}

async function reconcileResponse(
  response: Response,
  context: ReconciliationContext,
): Promise<ResultSerial<unknown, Problem>> {
  if (response.ok && !isJson(response)) {
    // Preserve downloads, streams, and other non-JSON success bodies untouched.
    return ['ok', response];
  }

  const textResult = await readText(response, context);
  if (textResult[0] === 'err') return textResult;
  const text = textResult[1];

  if (response.ok) {
    if (text === '') return ['ok', undefined];
    try {
      const parsed: unknown = JSON.parse(text);
      const problem = findNestedProblem(parsed);
      return problem === undefined ? ['ok', parsed] : ['err', problem];
    } catch (error) {
      return [
        'err',
        createTransportProblem(
          context.problems,
          context.backendKey,
          `Successful JSON response could not be decoded: ${errorDetail(error)}`,
        ),
      ];
    }
  }

  if (isJson(response) && text !== '') {
    try {
      const parsed: unknown = JSON.parse(text);
      const problem = findNestedProblem(parsed);
      if (problem !== undefined) return ['err', { ...problem, status: response.status }];
      return ['err', createUpstreamProblem(context.problems, context.backendKey, response.status, errorDetail(parsed))];
    } catch {
      // A response claiming JSON but carrying invalid bytes is a transport/body failure.
    }
  }

  const detail = text === '' ? response.statusText || 'The upstream returned no problem body.' : text;
  return [
    'err',
    createTransportProblem(
      context.problems,
      context.backendKey,
      `HTTP ${response.status} did not contain a usable Problem: ${detail}`,
    ),
  ];
}

async function reconcileFailure(
  error: unknown,
  context: ReconciliationContext,
): Promise<ResultSerial<unknown, Problem>> {
  const problem = findNestedProblem(error);
  if (problem !== undefined) return ['err', problem];

  const response = nestedResponse(error);
  if (response !== undefined) return reconcileResponse(response, context);

  const status = receivedStatus(error);
  const body = nestedJsonBody(error);
  if (status !== undefined && body !== undefined) {
    return ['err', createUpstreamProblem(context.problems, context.backendKey, status, errorDetail(body))];
  }

  return ['err', createTransportProblem(context.problems, context.backendKey, errorDetail(error))];
}

/** Collapse every supported SDK/fetch outcome to a Result serial that never rejects. */
export async function reconcileApiValue(
  value: unknown,
  context: ReconciliationContext,
): Promise<ResultSerial<unknown, Problem>> {
  try {
    if (isPromiseLike(value)) return reconcileApiValue(await value, context);
    if (isResultLike(value)) {
      const serial = await value.serial();
      return serial[0] === 'ok' ? reconcileApiValue(serial[1], context) : reconcileFailure(serial[1], context);
    }
    if (value instanceof Response) return reconcileResponse(value, context);
    const problem = findNestedProblem(value);
    return problem === undefined ? ['ok', value] : ['err', problem];
  } catch (error) {
    return reconcileFailure(error, context);
  }
}

export async function reconcileApiFailure(
  error: unknown,
  context: ReconciliationContext,
): Promise<ResultSerial<never, Problem>> {
  const serial = await reconcileFailure(error, context);
  if (serial[0] === 'err') return serial;
  return [
    'err',
    createTransportProblem(
      context.problems,
      context.backendKey,
      'A rejected API invocation unexpectedly contained a successful response.',
    ),
  ];
}
