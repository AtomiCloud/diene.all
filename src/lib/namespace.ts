/** Freeze member bindings while removing CommonJS interop-only markers. */
export function freezeNamespace<T extends object>(source: T): Readonly<T> {
  const bindings = { ...source } as T & { __esModule?: unknown };
  delete bindings.__esModule;
  return Object.freeze(bindings);
}
