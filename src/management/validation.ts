import { isIP } from 'node:net';
import { ManagementError } from './errors.ts';
import { type EndpointTarget, MAX_RETRY_WINDOW_SECONDS, type Quota } from './types.ts';

const DNS_LABEL = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/;
const SUPPORTED_PROVIDERS = [
  'airwallex',
  'apple-app-store',
  'discord',
  'google-play',
  'logto',
  'stripe',
  'telegram',
] as const;
const SUPPORTED_PROVIDER_SET = new Set<string>(SUPPORTED_PROVIDERS);
const PROVIDER = /^[a-z][a-z0-9_-]{0,62}$/;
const SERVICE_NAME = /^[a-z][a-z0-9-]{0,62}$/;
const INTAKE_SLUG = /^[A-Za-z0-9._~-]+$/;

export function validateAccountName(name: string, kind: 'internal' | 'external'): void {
  const prefix = `${kind}/`;
  if (!name.startsWith(prefix) || name.length <= prefix.length) {
    throw new ManagementError('invalid', `account name must use the ${prefix}<name> partition`);
  }
}

export function validateTenantName(name: string, source: 'api' | 'cr'): void {
  const requiredPrefix = source === 'cr' ? 'internal/' : 'external/';
  if (!name.startsWith(requiredPrefix) || name.length <= requiredPrefix.length) {
    throw new ManagementError('invalid', `${source} tenants must use the ${requiredPrefix}<name> partition`);
  }
}

export function validateVlandscape(value: string): void {
  if (!DNS_LABEL.test(value)) {
    throw new ManagementError('invalid', 'invalid home vlandscape');
  }
}

export function validateIntakeSlug(value: string): void {
  if (value.length === 0 || value.length > 128 || !INTAKE_SLUG.test(value)) {
    throw new ManagementError('invalid', 'intake slug must be a URL-safe path segment');
  }
}

export function validateQuota(input: Omit<Quota, 'tenantId' | 'updatedAt'>): void {
  for (const [key, value] of Object.entries(input)) {
    if (!Number.isSafeInteger(value) || value <= 0) {
      throw new ManagementError('invalid', `${key} must be a positive integer`);
    }
  }
  if (input.retryWindowSeconds > MAX_RETRY_WINDOW_SECONDS) {
    throw new ManagementError('invalid', `retryWindowSeconds cannot exceed ${MAX_RETRY_WINDOW_SECONDS}`);
  }
  if (input.dedupWindowSeconds !== MAX_RETRY_WINDOW_SECONDS) {
    throw new ManagementError('invalid', `dedupWindowSeconds must equal ${MAX_RETRY_WINDOW_SECONDS} in v1`);
  }
}

export function validateRoute(path: string, provider: string, scheme?: string): void {
  if (!path.startsWith('/') || path.includes('?') || path.includes('#') || path.includes('//')) {
    throw new ManagementError('invalid', 'route path must be an absolute path without query or fragment');
  }
  if (!PROVIDER.test(provider) || !SUPPORTED_PROVIDER_SET.has(provider)) {
    throw new ManagementError('invalid', 'unsupported provider');
  }
  if (scheme !== undefined && !PROVIDER.test(scheme)) {
    throw new ManagementError('invalid', 'invalid verification scheme');
  }
}

export function validateRegisteredUrl(input: {
  value: string;
  routePath: string;
  intakeSlug: string;
  homeVlandscape: string;
  customDomains: readonly string[];
}): void {
  let parsed: URL;
  try {
    parsed = new URL(input.value);
  } catch {
    throw new ManagementError('invalid', 'registered URL is invalid');
  }
  if (
    parsed.protocol !== 'https:' ||
    parsed.username !== '' ||
    parsed.password !== '' ||
    parsed.port !== '' ||
    parsed.search !== '' ||
    parsed.hash !== ''
  ) {
    throw new ManagementError(
      'invalid',
      'registered URL must be an exact HTTPS URL without userinfo, port, query, or fragment',
    );
  }
  const hostname = parsed.hostname.toLowerCase();
  const custom = input.customDomains.some(domain => domain.toLowerCase() === hostname);
  const expectedPath = custom ? input.routePath : `/t/${input.intakeSlug}${input.routePath}`;
  const canonicalSuffix = `.${input.homeVlandscape}.cluster.atomi.cloud`;
  if ((!custom && !hostname.endsWith(canonicalSuffix)) || parsed.pathname !== expectedPath) {
    throw new ManagementError(
      'invalid',
      'registered URL must match the tenant canonical path or an exactly registered custom domain',
    );
  }
}

export function validateEndpointTarget(target: EndpointTarget, tenantSource: 'api' | 'cr'): void {
  if (target.kind === 'url') {
    if (tenantSource === 'cr') {
      throw new ManagementError('invalid', 'internal CR tenants must use coordinate endpoints');
    }
    let parsed: URL;
    try {
      parsed = new URL(target.url);
    } catch {
      throw new ManagementError('invalid', 'endpoint URL is invalid');
    }
    if (parsed.protocol !== 'https:' || parsed.username || parsed.password || parsed.port || parsed.hash) {
      throw new ManagementError('invalid', 'external endpoint must be HTTPS on port 443 without userinfo or fragment');
    }
    validatePublicEndpointHostname(parsed.hostname);
    return;
  }
  if (tenantSource !== 'cr') {
    throw new ManagementError('invalid', 'external API tenants cannot register internal coordinates');
  }
  for (const value of [target.service, target.module, target.canonicalVlandscape]) {
    if (!SERVICE_NAME.test(value)) {
      throw new ManagementError('invalid', 'invalid endpoint coordinate');
    }
  }
}

function ipv4Octets(address: string): readonly number[] | undefined {
  const pieces = address.split('.');
  if (pieces.length !== 4) return undefined;
  const octets = pieces.map(piece => (/^\d{1,3}$/.test(piece) ? Number(piece) : -1));
  return octets.every(octet => octet >= 0 && octet <= 255) ? octets : undefined;
}

function isPublicIpv4(address: string): boolean {
  const octets = ipv4Octets(address);
  if (octets === undefined) return false;
  const [first, second, third, fourth] = octets;
  if (first === undefined || second === undefined || third === undefined || fourth === undefined) return false;
  if (first === 0 || first === 10 || first === 127 || first >= 224) return false;
  if (first === 100 && second >= 64 && second <= 127) return false;
  if (first === 169 && second === 254) return false;
  if (first === 172 && second >= 16 && second <= 31) return false;
  if (first === 192 && second === 168) return false;
  if (first === 192 && second === 0 && third === 0) return false;
  if (first === 192 && second === 0 && third === 2) return false;
  if (first === 192 && second === 88 && third === 99) return false;
  if (first === 198 && (second === 18 || second === 19)) return false;
  if (first === 198 && second === 51 && third === 100) return false;
  if (first === 203 && second === 0 && third === 113) return false;
  return !(first === 255 && second === 255 && third === 255 && fourth === 255);
}

function ipv6Hextets(address: string): readonly number[] | undefined {
  if (address.includes('%') || address.split('::').length > 2) return undefined;
  let normalized = address.toLowerCase();
  const ipv4Index = normalized.lastIndexOf(':');
  const ipv4Tail = normalized.slice(ipv4Index + 1);
  if (ipv4Tail.includes('.')) {
    const octets = ipv4Octets(ipv4Tail);
    if (octets === undefined || ipv4Index < 0) return undefined;
    const [first, second, third, fourth] = octets;
    if (first === undefined || second === undefined || third === undefined || fourth === undefined) return undefined;
    normalized = `${normalized.slice(0, ipv4Index)}:${((first << 8) | second).toString(16)}:${((third << 8) | fourth).toString(16)}`;
  }

  const [leftText = '', rightText = ''] = normalized.split('::');
  const left = leftText.length === 0 ? [] : leftText.split(':');
  const right = rightText.length === 0 ? [] : rightText.split(':');
  if (left.some(part => !/^[a-f0-9]{1,4}$/.test(part)) || right.some(part => !/^[a-f0-9]{1,4}$/.test(part))) {
    return undefined;
  }
  const compressed = normalized.includes('::');
  const missing = 8 - left.length - right.length;
  if ((!compressed && missing !== 0) || (compressed && missing < 1)) return undefined;
  return [...left, ...Array.from({ length: missing }, () => '0'), ...right].map(part => Number.parseInt(part, 16));
}

function isPublicIpv6(address: string): boolean {
  const hextets = ipv6Hextets(address);
  if (hextets === undefined || hextets.length !== 8) return false;
  const first = hextets[0];
  const second = hextets[1];
  if (first === undefined || second === undefined || first < 0x2000 || first > 0x3fff) return false;
  if (first === 0x2001 && second <= 0x01ff) return false;
  if (first === 0x2002 || first === 0x3ffe) return false;
  if (first === 0x3fff && second <= 0x0fff) return false;
  return !(first === 0x2001 && second === 0x0db8);
}

function isForbiddenEndpointAddress(address: string): boolean {
  const normalized =
    address
      .toLowerCase()
      .replace(/^\[|\]$/g, '')
      .split('%')[0] ?? '';
  const family = isIP(normalized);
  return family === 4 ? !isPublicIpv4(normalized) : family === 6 && !isPublicIpv6(normalized);
}

export function validatePublicEndpointHostname(hostname: string): void {
  const normalized = hostname
    .toLowerCase()
    .replace(/^\[|\]$/g, '')
    .replace(/\.$/, '');
  if (
    normalized === 'localhost' ||
    normalized === 'metadata.google.internal' ||
    normalized === 'metadata.aws.internal' ||
    normalized === 'metadata.azure.internal' ||
    normalized === 'instance-data.ec2.internal' ||
    normalized.endsWith('.localhost') ||
    normalized.endsWith('.local') ||
    normalized.endsWith('.internal') ||
    normalized.endsWith('.home.arpa') ||
    normalized.endsWith('.svc') ||
    normalized.endsWith('.svc.cluster.local') ||
    normalized.endsWith('.cluster.local') ||
    isForbiddenEndpointAddress(normalized)
  ) {
    throw new ManagementError('invalid', 'external endpoint destination is not public');
  }
}

export function validateResolvedEndpointAddresses(addresses: readonly string[]): void {
  if (
    addresses.length === 0 ||
    addresses.length > 16 ||
    addresses.some(address => isIP(address) === 0 || isForbiddenEndpointAddress(address))
  ) {
    throw new ManagementError('invalid', 'external endpoint DNS resolved to a forbidden address');
  }
}

export function normalizeHostname(hostname: string): string {
  const normalized = hostname.trim().toLowerCase().replace(/\.$/, '');
  if (
    normalized.length > 253 ||
    normalized.split('.').length < 2 ||
    normalized.split('.').some(label => !DNS_LABEL.test(label))
  ) {
    throw new ManagementError('invalid', 'invalid custom domain hostname');
  }
  return normalized;
}

export function assertSecretPointer(pointer: string): void {
  if (!/^\/[A-Za-z0-9._-]{1,253}$/.test(pointer) || pointer === '/.' || pointer === '/..') {
    throw new ManagementError(
      'invalid',
      'secret references must be one logical slash plus one Kubernetes Secret filename key',
    );
  }
}
