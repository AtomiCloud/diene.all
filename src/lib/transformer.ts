import { isRecord } from '@atomicloud/diene.core-utils';
import type { z } from 'zod';
import { createProblem } from './registry.js';
import type { Problem, RegisteredProblem } from './types.js';

function isStatus(value: unknown): value is number {
  return Number.isInteger(value) && (value as number) >= 100 && (value as number) <= 599;
}

export function isProblem(value: unknown): value is Problem {
  return (
    isRecord(value) &&
    typeof value.type === 'string' &&
    typeof value.title === 'string' &&
    isStatus(value.status) &&
    'data' in value
  );
}

function nestedError(value: unknown): unknown {
  if (!isRecord(value)) {
    return undefined;
  }
  return value.problem ?? value.error ?? value.cause;
}

function errorDetail(value: unknown): string {
  if (value instanceof Error) {
    return value.message;
  }
  if (isRecord(value)) {
    if (typeof value.detail === 'string') {
      return value.detail;
    }
    if (typeof value.message === 'string') {
      return value.message;
    }
  }
  return typeof value === 'string' ? value : 'An unexpected error occurred';
}

export interface ProblemTransformerOptions<TSchema extends z.ZodType> {
  readonly fallback: RegisteredProblem<TSchema>;
  readonly fallbackData: (error: unknown) => z.input<TSchema>;
  readonly instance?: (error: unknown) => string | undefined;
}

export class ProblemTransformer<TSchema extends z.ZodType> {
  constructor(readonly options: ProblemTransformerOptions<TSchema>) {}

  fromError(error: unknown): Problem {
    const visited = new Set<object>();
    let current = error;

    while (true) {
      if (isProblem(current)) {
        return current;
      }

      if (isRecord(current)) {
        visited.add(current);
      }
      const nested = nestedError(current);
      if (nested === undefined || (isRecord(nested) && visited.has(nested))) {
        break;
      }
      current = nested;
    }

    return createProblem(this.options.fallback, {
      detail: errorDetail(current),
      instance: this.options.instance?.(current),
      data: this.options.fallbackData(current),
    });
  }

  async fromHttpError(response: Response): Promise<Problem> {
    const text = await response.text();
    let body: unknown = text;
    if (text !== '') {
      try {
        body = JSON.parse(text);
      } catch {
        body = text;
      }
    }

    if (isProblem(body)) {
      return { ...body, status: response.status };
    }

    const nested = nestedError(body);
    if (isProblem(nested)) {
      return { ...nested, status: response.status };
    }

    return createProblem(this.options.fallback, {
      detail: text === '' ? response.statusText || 'HTTP request failed' : errorDetail(body),
      status: response.status,
      instance: response.url || this.options.instance?.(body),
      data: this.options.fallbackData(body),
    });
  }
}

export function fromError<TSchema extends z.ZodType>(
  error: unknown,
  options: ProblemTransformerOptions<TSchema>,
): Problem {
  return new ProblemTransformer(options).fromError(error);
}

export async function fromHttpError<TSchema extends z.ZodType>(
  response: Response,
  options: ProblemTransformerOptions<TSchema>,
): Promise<Problem> {
  return new ProblemTransformer(options).fromHttpError(response);
}
