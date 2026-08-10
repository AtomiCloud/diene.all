import type { ErrorPortalConfig } from './types.js';

const segmentPattern = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const problemIdPattern = /^[a-z][a-z0-9_]*$/;
const versionPattern = /^v[0-9]+$/;

function validateSegment(name: string, value: string, pattern = segmentPattern): void {
  if (!pattern.test(value)) {
    throw new RangeError(`${name} must match ${pattern}; received ${JSON.stringify(value)}`);
  }
}

function validateHost(scheme: ErrorPortalConfig['scheme'], host: string): void {
  if (host.trim() !== host || host === '' || /[/\\\s@?#]/.test(host)) {
    throw new RangeError('ErrorPortal host must be a non-empty host or host:port without URL components');
  }

  try {
    const origin = new URL(`${scheme}://${host}/`);
    if (
      origin.host !== host ||
      origin.username !== '' ||
      origin.password !== '' ||
      origin.pathname !== '/' ||
      origin.search !== '' ||
      origin.hash !== ''
    ) {
      throw new RangeError('ErrorPortal host is not a canonical host or host:port');
    }
  } catch (error: unknown) {
    if (error instanceof RangeError && error.message.startsWith('ErrorPortal')) {
      throw error;
    }
    throw new RangeError(`Invalid ErrorPortal host ${JSON.stringify(host)}`, { cause: error });
  }
}

export function buildProblemTypeUri(config: ErrorPortalConfig, version: string, id: string): string {
  validateHost(config.scheme, config.host);

  validateSegment('landscape', config.landscape);
  validateSegment('platform', config.platform);
  validateSegment('service', config.service);
  validateSegment('module', config.module);
  validateSegment('version', version, versionPattern);
  validateSegment('id', id, problemIdPattern);

  const origin = config.scheme.concat('://', config.host, '/');
  const path = ['docs', config.landscape, config.platform, config.service, config.module, version, id].join('/');
  return new URL(path, origin).toString();
}
