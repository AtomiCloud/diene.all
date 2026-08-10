import type { z } from 'zod';

export type JsonSchema = Readonly<Record<string, unknown>>;

export interface ErrorPortalConfig {
  readonly scheme: 'http' | 'https';
  readonly host: string;
  readonly landscape: string;
  readonly platform: string;
  readonly service: string;
  readonly module: string;
}

export interface ProblemDefinition<TSchema extends z.ZodType = z.ZodType> {
  readonly id: string;
  readonly title: string;
  readonly status: number;
  readonly version: string;
  readonly dataSchema: TSchema;
}

export interface RegisteredProblem<TSchema extends z.ZodType = z.ZodType> extends ProblemDefinition<TSchema> {
  readonly type: string;
}

export type ProblemData<TDefinition extends ProblemDefinition> = z.output<TDefinition['dataSchema']>;

export interface Problem<TData = unknown> {
  readonly type: string;
  readonly title: string;
  readonly status: number;
  readonly detail?: string;
  readonly instance?: string;
  readonly data: TData;
}

export type ProblemDetail<TData = unknown> = Problem<TData>;

export interface ProblemInit<TData> {
  readonly detail?: string;
  readonly instance?: string;
  readonly status?: number;
  readonly data: TData;
}

export interface ProblemEndpoint {
  readonly method: string;
  readonly path: string;
}

export interface ProblemManifestEntry {
  readonly id: string;
  readonly type: string;
  readonly title: string;
  readonly status: number;
  readonly version: string;
  readonly data: JsonSchema;
}

export interface ProblemManifest {
  readonly problems: readonly ProblemManifestEntry[];
  readonly schemas: Readonly<Record<string, JsonSchema>>;
}

export interface ProblemCatalogEntry {
  readonly id: string;
  readonly type: string;
  readonly title: string;
  readonly status: number;
  readonly recoverable: boolean;
  readonly data: JsonSchema;
  readonly endpoints: readonly ProblemEndpoint[];
}

export interface ProblemCatalogDeclaration {
  readonly recoverable: boolean;
  readonly endpoints: readonly ProblemEndpoint[];
}

export interface ProblemResourceIdentity {
  readonly platform: string;
  readonly service: string;
  readonly landscape: string;
  readonly version: string;
}

export interface ProblemResourceEntry {
  readonly id: string;
  readonly type: string;
  readonly title: string;
  readonly status: number;
  readonly recoverable: boolean;
  readonly schema: JsonSchema;
  readonly endpoints: readonly ProblemEndpoint[];
}

export interface ProblemResource {
  readonly apiVersion: 'atomi.cloud/v1alpha1';
  readonly kind: 'Problem';
  readonly metadata: {
    readonly name: string;
    readonly namespace: string;
  };
  readonly spec: {
    readonly platform: string;
    readonly service: string;
    readonly landscape: string;
    readonly version: string;
    readonly problems: readonly ProblemResourceEntry[];
  };
}
