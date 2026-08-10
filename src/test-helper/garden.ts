const DNS_LABEL = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/;

/** The service-tree coordinates encoded by a final Garden instance hostname. */
export interface GardenNamespaceFixture {
  readonly module: string;
  readonly service: string;
  readonly platform: string;
  readonly instance: string;
  readonly landscape: string;
  readonly zone: string;
}

export interface GardenPreviewEndpointOptions {
  /** Final hostname: `module.service.platform.instance.landscape.zone`. */
  readonly hostname: string;
  /** Expected namespace fixture; every coordinate must match the hostname. */
  readonly namespace: GardenNamespaceFixture;
  /** HTTPS is the safe default; HTTP must be explicit. */
  readonly protocol?: 'http' | 'https';
  readonly port?: number;
  readonly path?: string;
}

export class E2eHarnessError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'E2eHarnessError';
  }
}

function validateDnsName(value: string, label: string): string {
  if (value === '' || value.length > 253 || value.split('.').some(part => !DNS_LABEL.test(part))) {
    throw new E2eHarnessError(`${label} must be a lowercase DNS name`);
  }
  return value;
}

/** Resolve one Garden preview endpoint while proving the namespace fixture matches. */
export function resolveGardenPreviewEndpoint(options: GardenPreviewEndpointOptions): string {
  const { namespace } = options;
  const module = validateDnsName(namespace.module, 'namespace.module');
  const service = validateDnsName(namespace.service, 'namespace.service');
  const platform = validateDnsName(namespace.platform, 'namespace.platform');
  const instance = validateDnsName(namespace.instance, 'namespace.instance');
  const landscape = validateDnsName(namespace.landscape, 'namespace.landscape');
  const zone = validateDnsName(namespace.zone, 'namespace.zone');
  const hostname = validateDnsName(options.hostname, 'hostname');
  const expected = [module, service, platform, instance, landscape, zone].join('.');

  if (hostname !== expected) {
    throw new E2eHarnessError(`Garden hostname does not match namespace fixture: expected ${expected}`);
  }
  if (options.port !== undefined && (!Number.isInteger(options.port) || options.port < 1 || options.port > 65_535)) {
    throw new E2eHarnessError('port must be an integer from 1 through 65535');
  }
  const path = options.path ?? '/';
  if (!path.startsWith('/') || path.startsWith('//')) {
    throw new E2eHarnessError('path must be an absolute URL path');
  }

  const endpoint = new URL(`${options.protocol ?? 'https'}://${hostname}`);
  if (options.port !== undefined) endpoint.port = String(options.port);
  endpoint.pathname = path;
  return endpoint.toString();
}
