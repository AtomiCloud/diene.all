import { lookup as dnsLookup } from 'node:dns/promises';
import type { IncomingHttpHeaders } from 'node:http';
import { request as httpsRequest } from 'node:https';
import { isIP } from 'node:net';
import { Err, Ok, type Result } from '@atomicloud/diene.result';
import type {
  DeliveryRequest,
  DeliveryResponse,
  DeliveryTransport,
  HeaderMap,
  TransportFailure,
} from '../domain/index.ts';

type DeliveryAddressKind = 'canonical' | 'external' | 'local';

const deliveryAddressKind: unique symbol = Symbol('mercury.delivery-address-kind');

type PolicyAwareDeliveryRequest = DeliveryRequest & {
  readonly [deliveryAddressKind]: DeliveryAddressKind;
};

export const withDeliveryAddressKind = (
  request: DeliveryRequest,
  addressKind: DeliveryAddressKind,
): DeliveryRequest => {
  const policyAware: PolicyAwareDeliveryRequest = {
    ...request,
    [deliveryAddressKind]: addressKind,
  };
  return policyAware;
};

interface ResolvedDestinationAddress {
  readonly address: string;
  readonly family: 4 | 6;
}

export type ExternalDestinationResolver = (hostname: string) => Promise<readonly ResolvedDestinationAddress[]>;

interface ApprovedExternalDestination extends ResolvedDestinationAddress {
  readonly hostname: string;
  readonly url: URL;
}

export type PinnedExternalSender = (
  request: DeliveryRequest,
  destination: ApprovedExternalDestination,
  signal: AbortSignal,
) => Promise<DeliveryResponse>;

class DestinationPolicyError extends Error {}

const responseHeaders = (headers: Headers): HeaderMap => Object.fromEntries(headers.entries());

const incomingResponseHeaders = (headers: IncomingHttpHeaders): HeaderMap =>
  Object.fromEntries(
    Object.entries(headers).flatMap(([name, value]) => {
      if (value === undefined) return [];
      return [[name, Array.isArray(value) ? value.join(', ') : String(value)]];
    }),
  );

const blockedHostnameSuffixes = ['.cluster.local', '.home.arpa', '.internal', '.local', '.localhost', '.svc'] as const;

const blockedHostnames = new Set([
  'instance-data.ec2.internal',
  'localhost',
  'metadata.azure.internal',
  'metadata.google.internal',
]);

const normalizedHostname = (hostname: string): string => {
  const withoutBrackets = hostname.startsWith('[') && hostname.endsWith(']') ? hostname.slice(1, -1) : hostname;
  return withoutBrackets.toLowerCase().replace(/\.$/, '');
};

const isBlockedHostname = (hostname: string): boolean =>
  blockedHostnames.has(hostname) || blockedHostnameSuffixes.some(suffix => hostname.endsWith(suffix));

const ipv4Octets = (address: string): readonly number[] | null => {
  const pieces = address.split('.');
  if (pieces.length !== 4) return null;
  const octets = pieces.map(piece => (/^\d{1,3}$/.test(piece) ? Number(piece) : -1));
  return octets.every(octet => octet >= 0 && octet <= 255) ? octets : null;
};

const isPublicIpv4 = (address: string): boolean => {
  const octets = ipv4Octets(address);
  if (octets === null) return false;
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
};

const ipv6Hextets = (address: string): readonly number[] | null => {
  if (address.includes('%') || address.split('::').length > 2) return null;
  let normalized = address.toLowerCase();
  const ipv4Index = normalized.lastIndexOf(':');
  const ipv4Tail = normalized.slice(ipv4Index + 1);
  if (ipv4Tail.includes('.')) {
    const octets = ipv4Octets(ipv4Tail);
    if (octets === null || ipv4Index < 0) return null;
    const [first, second, third, fourth] = octets;
    if (first === undefined || second === undefined || third === undefined || fourth === undefined) return null;
    normalized = `${normalized.slice(0, ipv4Index)}:${((first << 8) | second).toString(16)}:${((third << 8) | fourth).toString(16)}`;
  }

  const [leftText = '', rightText = ''] = normalized.split('::');
  const left = leftText.length === 0 ? [] : leftText.split(':');
  const right = rightText.length === 0 ? [] : rightText.split(':');
  if (left.some(part => !/^[a-f0-9]{1,4}$/.test(part)) || right.some(part => !/^[a-f0-9]{1,4}$/.test(part))) {
    return null;
  }
  const compressed = normalized.includes('::');
  const missing = 8 - left.length - right.length;
  if ((!compressed && missing !== 0) || (compressed && missing < 1)) return null;
  return [...left, ...Array.from({ length: missing }, () => '0'), ...right].map(part => Number.parseInt(part, 16));
};

const isPublicIpv6 = (address: string): boolean => {
  const hextets = ipv6Hextets(address);
  if (hextets === null || hextets.length !== 8) return false;
  const first = hextets[0];
  const second = hextets[1];
  if (first === undefined || second === undefined || first < 0x2000 || first > 0x3fff) return false;
  if (first === 0x2001 && second <= 0x01ff) return false;
  if (first === 0x2002 || first === 0x3ffe) return false;
  if (first === 0x3fff && second <= 0x0fff) return false;
  return !(first === 0x2001 && second === 0x0db8);
};

export const isPublicDeliveryAddress = (address: string): boolean => {
  const family = isIP(address);
  return family === 4 ? isPublicIpv4(address) : family === 6 && isPublicIpv6(address);
};

const defaultResolver: ExternalDestinationResolver = async hostname =>
  (await dnsLookup(hostname, { all: true, verbatim: true })).flatMap(result =>
    result.family === 4 || result.family === 6 ? [{ address: result.address, family: result.family }] : [],
  );

const approveExternalDestination = async (
  rawUrl: string,
  resolver: ExternalDestinationResolver,
): Promise<ApprovedExternalDestination> => {
  let url: URL;
  try {
    url = new URL(rawUrl);
  } catch {
    throw new DestinationPolicyError('external delivery URL is malformed');
  }
  if (
    url.protocol !== 'https:' ||
    url.username.length > 0 ||
    url.password.length > 0 ||
    url.hash.length > 0 ||
    (url.port.length > 0 && url.port !== '443')
  ) {
    throw new DestinationPolicyError('external delivery requires an HTTPS destination on port 443');
  }
  const hostname = normalizedHostname(url.hostname);
  if (hostname.length === 0 || hostname.length > 253 || isBlockedHostname(hostname)) {
    throw new DestinationPolicyError('external delivery hostname is not allowed');
  }

  const literalFamily = isIP(hostname);
  const resolved: readonly ResolvedDestinationAddress[] =
    literalFamily === 4 || literalFamily === 6
      ? [{ address: hostname, family: literalFamily }]
      : await resolver(hostname);
  if (resolved.length === 0 || resolved.length > 16) {
    throw new DestinationPolicyError('external delivery DNS result is empty or unbounded');
  }
  const unique = [...new Map(resolved.map(result => [`${result.family}:${result.address}`, result] as const)).values()];
  if (
    unique.some(
      result =>
        (result.family !== 4 && result.family !== 6) ||
        isIP(result.address) !== result.family ||
        !isPublicDeliveryAddress(result.address),
    )
  ) {
    throw new DestinationPolicyError('external delivery DNS resolved to a non-public address');
  }
  const selected = unique[0];
  if (selected === undefined) {
    throw new DestinationPolicyError('external delivery DNS produced no usable address');
  }
  return { ...selected, hostname, url };
};

const defaultPinnedExternalSender: PinnedExternalSender = (request, destination, signal) =>
  new Promise((resolve, reject) => {
    const headers = {
      ...request.headers,
      'content-length': String(request.body.byteLength),
      host: destination.url.host,
    };
    const client = httpsRequest(
      {
        agent: false,
        headers,
        hostname: destination.hostname,
        lookup: (_hostname, _options, callback) => callback(null, destination.address, destination.family),
        method: 'POST',
        path: `${destination.url.pathname}${destination.url.search}`,
        port: 443,
        protocol: 'https:',
        ...(isIP(destination.hostname) === 0 ? { servername: destination.hostname } : {}),
      },
      response => {
        const status = response.statusCode;
        const headers = incomingResponseHeaders(response.headers);
        response.destroy();
        if (status === undefined) {
          reject(new Error('external delivery response omitted its status'));
          return;
        }
        resolve({ headers, status });
      },
    );
    const cancelled = (): void => {
      client.destroy(signal.reason instanceof Error ? signal.reason : undefined);
    };
    signal.addEventListener('abort', cancelled, { once: true });
    client.once('close', () => signal.removeEventListener('abort', cancelled));
    client.once('error', reject);
    client.end(request.body);
  });

const awaitWithCancellation = async <Value>(operation: Promise<Value>, signal: AbortSignal): Promise<Value> => {
  if (signal.aborted) throw signal.reason ?? new DOMException('delivery cancelled', 'AbortError');
  let cancelled: (() => void) | undefined;
  const cancellation = new Promise<never>((_resolve, reject) => {
    cancelled = (): void => reject(signal.reason ?? new DOMException('delivery cancelled', 'AbortError'));
    signal.addEventListener('abort', cancelled, { once: true });
  });
  try {
    return await Promise.race([operation, cancellation]);
  } finally {
    if (cancelled !== undefined) signal.removeEventListener('abort', cancelled);
  }
};

export class FetchDeliveryTransport implements DeliveryTransport {
  constructor(
    readonly fetcher: typeof fetch = fetch,
    readonly timeoutMs = 10_000,
    readonly resolver: ExternalDestinationResolver = defaultResolver,
    readonly pinnedExternalSender: PinnedExternalSender = defaultPinnedExternalSender,
  ) {
    if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1) {
      throw new RangeError('delivery request timeout must be a positive integer millisecond duration');
    }
  }

  async send(request: DeliveryRequest): Promise<Result<DeliveryResponse, TransportFailure>> {
    if (request.signal?.aborted === true) {
      return Err({
        code: 'cancelled',
        message: 'delivery request cancelled before dispatch',
      });
    }
    const controller = new AbortController();
    let cancelled = false;
    let timedOut = false;
    const cancel = (): void => {
      cancelled = true;
      controller.abort(request.signal?.reason);
    };
    request.signal?.addEventListener('abort', cancel, { once: true });
    const timeout = setTimeout(() => {
      timedOut = true;
      controller.abort(new DOMException('delivery request timed out', 'TimeoutError'));
    }, this.timeoutMs);
    try {
      const addressKind = (request as Partial<PolicyAwareDeliveryRequest>)[deliveryAddressKind] ?? 'external';
      if (addressKind === 'external') {
        const destination = await awaitWithCancellation(
          approveExternalDestination(request.url, this.resolver),
          controller.signal,
        );
        return Ok(
          await awaitWithCancellation(
            this.pinnedExternalSender(request, destination, controller.signal),
            controller.signal,
          ),
        );
      }

      const response = await this.fetcher(request.url, {
        method: 'POST',
        headers: request.headers,
        body: request.body,
        redirect: 'error',
        signal: controller.signal,
      });
      try {
        await response.body?.cancel();
      } catch {
        // Response bodies are ignored by contract; cancellation is best effort.
      }
      return Ok({
        status: response.status,
        headers: responseHeaders(response.headers),
      });
    } catch (error) {
      return Err({
        code: cancelled
          ? 'cancelled'
          : timedOut
            ? 'timeout'
            : error instanceof DestinationPolicyError
              ? 'unavailable'
              : 'network',
        message: error instanceof Error ? error.message : String(error),
      });
    } finally {
      clearTimeout(timeout);
      request.signal?.removeEventListener('abort', cancel);
    }
  }
}
