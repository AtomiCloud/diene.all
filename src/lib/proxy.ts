import type { Problem } from '@atomicloud/diene.problems';
import { Res, type Result } from '@atomicloud/diene.result';

import { reconcileApiFailure, reconcileApiValue } from './reconcile';
import type { ApiClient, ReconciliationContext } from './types';

function isPromiseLike(value: unknown): value is PromiseLike<unknown> {
  return (
    (typeof value === 'object' || typeof value === 'function') &&
    value !== null &&
    typeof (value as { readonly then?: unknown }).then === 'function'
  );
}

function isNamespace(value: unknown): value is object {
  if (typeof value !== 'object' || value === null || isPromiseLike(value)) return false;
  if (
    value instanceof Response ||
    value instanceof Request ||
    value instanceof Headers ||
    value instanceof URL ||
    value instanceof Date ||
    value instanceof ArrayBuffer ||
    ArrayBuffer.isView(value)
  ) {
    return false;
  }
  return true;
}

async function invoke(
  method: (...args: readonly unknown[]) => unknown,
  owner: object,
  args: readonly unknown[],
  context: ReconciliationContext,
) {
  try {
    return await reconcileApiValue(Reflect.apply(method, owner, args), context);
  } catch (error) {
    return reconcileApiFailure(error, context);
  }
}

/** Recursively proxy a Kiota-shaped SDK. Every method immediately returns a Result. */
export function proxyApiClient<TClient extends object>(
  client: TClient,
  context: ReconciliationContext,
): ApiClient<TClient> {
  const wrap = (target: object): object =>
    new Proxy(target, {
      get(owner, property) {
        const value: unknown = Reflect.get(owner, property, owner);
        if (typeof value === 'function') {
          return (...args: readonly unknown[]): Result<unknown, Problem> => {
            return Res.fromSerial<unknown, Problem>(
              invoke(value as (...args: readonly unknown[]) => unknown, owner, args, context),
            );
          };
        }
        return isNamespace(value) ? wrap(value) : value;
      },
    });

  return wrap(client) as ApiClient<TClient>;
}
