import { Err, Ok, type Result } from '@atomicloud/diene.result';

export interface ModuleLifecycle<TContext = unknown> {
  readonly start?: (context: TContext) => void | Promise<void>;
  readonly stop?: (context: TContext) => void | Promise<void>;
}

export interface ModuleDefinition<TValue, TConfig = unknown, TContext = unknown> {
  readonly id: string;
  readonly create: (config: TConfig) => TValue;
  readonly lifecycle?: ModuleLifecycle<TContext>;
}

export type ModuleRegistrationError =
  | { readonly kind: 'invalid-id'; readonly id: string }
  | { readonly kind: 'duplicate-id'; readonly id: string };

export interface MissingModuleError {
  readonly kind: 'missing-module';
  readonly id: string;
}

const MODULE_ID = /^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$/;

export const defineModule = <TValue, TConfig = unknown, TContext = unknown>(
  definition: ModuleDefinition<TValue, TConfig, TContext>,
): ModuleDefinition<TValue, TConfig, TContext> => {
  if (!MODULE_ID.test(definition.id)) {
    throw new TypeError(`invalid module id: "${definition.id}"`);
  }
  return Object.freeze(definition);
};

export interface ModuleResolver {
  resolve<TValue>(id: string): Result<TValue, MissingModuleError>;
  has(id: string): boolean;
}

export interface ModuleRegistry extends ModuleResolver {
  register<TValue, TConfig, TContext>(
    definition: ModuleDefinition<TValue, TConfig, TContext>,
    config: TConfig,
  ): Result<TValue, ModuleRegistrationError>;
}

export const createModuleRegistry = (): ModuleRegistry => {
  const values = new Map<string, unknown>();

  return {
    register(definition, config) {
      if (!MODULE_ID.test(definition.id)) {
        return Err({ kind: 'invalid-id', id: definition.id });
      }
      if (values.has(definition.id)) {
        return Err({ kind: 'duplicate-id', id: definition.id });
      }
      const value = definition.create(config);
      values.set(definition.id, value);
      return Ok(value);
    },
    resolve<TValue>(id: string) {
      if (!values.has(id)) {
        return Err<TValue, MissingModuleError>({ kind: 'missing-module', id });
      }
      return Ok(values.get(id) as TValue);
    },
    has(id) {
      return values.has(id);
    },
  };
};
