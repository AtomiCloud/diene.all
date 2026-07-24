import type { TelemetryAttributes } from '@atomicloud/diene.interfaces';
import { resourceFromAttributes, type Resource } from '@opentelemetry/resources';
import {
  ATTR_DEPLOYMENT_ENVIRONMENT_NAME,
  ATTR_SERVICE_NAME,
  ATTR_SERVICE_NAMESPACE,
  ATTR_SERVICE_VERSION,
} from '@opentelemetry/semantic-conventions';
import { z } from 'zod';

const identityValueSchema = z.string().trim().min(1);

const appIdentitySchema = z
  .object({
    landscape: identityValueSchema,
    platform: identityValueSchema,
    service: identityValueSchema,
    module: identityValueSchema,
    version: identityValueSchema,
  })
  .strict()
  .readonly();

type AppIdentity = z.infer<typeof appIdentitySchema>;
type OtelEnvironment = Readonly<Record<string, string | undefined>>;

function mapResourceAttributes(identity: AppIdentity): TelemetryAttributes {
  const app = appIdentitySchema.parse(identity);
  return Object.freeze({
    [ATTR_DEPLOYMENT_ENVIRONMENT_NAME]: app.landscape,
    [ATTR_SERVICE_NAMESPACE]: app.platform,
    [ATTR_SERVICE_NAME]: app.service,
    [ATTR_SERVICE_VERSION]: app.version,
    'atomi.landscape': app.landscape,
    'atomi.module': app.module,
    'atomi.platform': app.platform,
    'atomi.service': app.service,
    'atomi.version': app.version,
  });
}

function parseOtelResourceAttributes(value: string | undefined): TelemetryAttributes {
  if (value === undefined || value.trim() === '') return Object.freeze({});
  const entries = value
    .split(',')
    .map(entry => entry.trim())
    .filter(entry => entry.length > 0)
    .map(entry => {
      const separator = entry.indexOf('=');
      if (separator <= 0) return undefined;
      const key = entry.slice(0, separator).trim();
      const attributeValue = entry.slice(separator + 1).trim();
      return key.length === 0 ? undefined : ([key, attributeValue] as const);
    })
    .filter((entry): entry is readonly [string, string] => entry !== undefined);
  return Object.freeze(Object.fromEntries(entries));
}

function resourceAttributes(identity: AppIdentity, environment: OtelEnvironment = process.env): TelemetryAttributes {
  const configured = mapResourceAttributes(identity);
  const standard = parseOtelResourceAttributes(environment.OTEL_RESOURCE_ATTRIBUTES);
  return Object.freeze({
    ...configured,
    ...standard,
    ...(environment.OTEL_SERVICE_NAME === undefined || environment.OTEL_SERVICE_NAME.trim() === ''
      ? {}
      : { [ATTR_SERVICE_NAME]: environment.OTEL_SERVICE_NAME.trim() }),
  });
}

function createOtelResource(identity: AppIdentity, environment: OtelEnvironment = process.env): Resource {
  return resourceFromAttributes(resourceAttributes(identity, environment));
}

export type { AppIdentity, OtelEnvironment };
export {
  appIdentitySchema,
  createOtelResource,
  mapResourceAttributes,
  parseOtelResourceAttributes,
  resourceAttributes,
};
