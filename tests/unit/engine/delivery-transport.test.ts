import { describe, it } from 'bun:test';
import should from 'should';
import {
  FetchDeliveryTransport,
  isPublicDeliveryAddress,
  withDeliveryAddressKind,
} from '../../../src/delivery/transport.ts';

const abortingFetcher = (onAbort: () => void): typeof fetch =>
  ((_: string | URL | Request, init?: RequestInit) =>
    new Promise<Response>((_resolve, reject) => {
      const signal = init?.signal;
      const abort = (): void => {
        onAbort();
        reject(signal?.reason ?? new DOMException('aborted', 'AbortError'));
      };
      if (signal?.aborted === true) {
        abort();
        return;
      }
      signal?.addEventListener('abort', abort, { once: true });
    })) as unknown as typeof fetch;

describe('FetchDeliveryTransport', () => {
  it('should bound normal delivery requests with the configured timeout', async () => {
    // Arrange
    let active = true;
    const subject = new FetchDeliveryTransport(
      abortingFetcher(() => {
        active = false;
      }),
      5,
    );

    // Act
    const result = await subject.send({
      ...withDeliveryAddressKind(
        {
          url: 'https://receiver.example/webhook',
          headers: {},
          body: new Uint8Array(),
        },
        'canonical',
      ),
    });

    // Assert
    should(await result.isErr()).be.true();
    should((await result.unwrapErr()).code).equal('timeout');
    should(active).be.false();
  });

  it('should apply one timeout across external DNS resolution and the pinned connection', async () => {
    // Arrange
    const externalRequest = withDeliveryAddressKind(
      {
        url: 'https://receiver.example/webhook',
        headers: {},
        body: new Uint8Array(),
      },
      'external',
    );
    const stalledResolution = new FetchDeliveryTransport(
      fetch,
      5,
      () => new Promise(() => undefined),
      async () => ({ status: 200, headers: {} }),
    );
    let senderAborted = false;
    const stalledSender = new FetchDeliveryTransport(
      fetch,
      5,
      async () => [{ address: '93.184.216.34', family: 4 }],
      (_request, _destination, signal) =>
        new Promise((_resolve, reject) => {
          const abort = (): void => {
            senderAborted = true;
            reject(signal.reason ?? new DOMException('aborted', 'AbortError'));
          };
          if (signal.aborted) abort();
          else signal.addEventListener('abort', abort, { once: true });
        }),
    );

    // Act
    const resolutionResult = await stalledResolution.send(externalRequest);
    const senderResult = await stalledSender.send(externalRequest);

    // Assert
    should(await resolutionResult.isErr()).be.true();
    should((await resolutionResult.unwrapErr()).code).equal('timeout');
    should(await senderResult.isErr()).be.true();
    should((await senderResult.unwrapErr()).code).equal('timeout');
    should(senderAborted).be.true();
  });

  it('should distinguish graceful shutdown cancellation from retryable timeouts', async () => {
    // Arrange
    let active = true;
    const controller = new AbortController();
    const subject = new FetchDeliveryTransport(
      abortingFetcher(() => {
        active = false;
      }),
      10_000,
    );

    // Act
    const pending = subject.send(
      withDeliveryAddressKind(
        {
          url: 'https://receiver.example/webhook',
          headers: {},
          body: new Uint8Array(),
          signal: controller.signal,
        },
        'canonical',
      ),
    );
    controller.abort(new DOMException('shutdown', 'AbortError'));
    const result = await pending;

    // Assert
    should(await result.isErr()).be.true();
    should((await result.unwrapErr()).code).equal('cancelled');
    should(active).be.false();
  });

  it('should disable redirects while allowing separately trusted coordinate connections', async () => {
    // Arrange
    let redirect: string | undefined;
    let resolved = false;
    const subject = new FetchDeliveryTransport(
      (async (_input, init) => {
        redirect = init?.redirect;
        return new Response(null, { status: 200 });
      }) as typeof fetch,
      1_000,
      async () => {
        resolved = true;
        return [];
      },
    );

    // Act
    const result = await subject.send(
      withDeliveryAddressKind(
        {
          url: 'http://checkout.acme.svc.cluster.local/internal/webhooks/stripe',
          headers: {},
          body: new Uint8Array(),
        },
        'local',
      ),
    );

    // Assert
    should(await result.isOk()).be.true();
    should(redirect).equal('error');
    should(resolved).be.false();
  });

  it('should reject private, loopback, link-local, metadata, cluster, and nonstandard-port destinations', async () => {
    // Arrange
    const blockedAddresses = [
      '0.0.0.0',
      '10.0.0.1',
      '100.64.0.1',
      '127.0.0.1',
      '169.254.169.254',
      '172.16.0.1',
      '192.168.0.1',
      '::1',
      'fd00::1',
      'fe80::1',
      '2001:db8::1',
    ];
    let dispatches = 0;
    const sender = async () => {
      dispatches += 1;
      return { status: 200, headers: {} };
    };

    // Act
    const addressResults = await Promise.all(
      blockedAddresses.map(address =>
        new FetchDeliveryTransport(
          fetch,
          1_000,
          async () => [{ address, family: address.includes(':') ? 6 : 4 }],
          sender,
        ).send(
          withDeliveryAddressKind(
            { url: 'https://receiver.example/webhook', headers: {}, body: new Uint8Array() },
            'external',
          ),
        ),
      ),
    );
    const blockedName = await new FetchDeliveryTransport(
      fetch,
      1_000,
      async () => {
        throw new Error('blocked metadata hostname must not reach DNS');
      },
      sender,
    ).send(
      withDeliveryAddressKind(
        { url: 'https://metadata.google.internal/computeMetadata/v1', headers: {}, body: new Uint8Array() },
        'external',
      ),
    );
    const blockedCluster = await new FetchDeliveryTransport(fetch, 1_000, async () => [], sender).send(
      withDeliveryAddressKind(
        { url: 'https://checkout.acme.svc.cluster.local/webhook', headers: {}, body: new Uint8Array() },
        'external',
      ),
    );
    const blockedPort = await new FetchDeliveryTransport(fetch, 1_000, async () => [], sender).send(
      withDeliveryAddressKind(
        { url: 'https://receiver.example:8443/webhook', headers: {}, body: new Uint8Array() },
        'external',
      ),
    );

    // Assert
    for (const result of [...addressResults, blockedName, blockedCluster, blockedPort]) {
      should(await result.isErr()).be.true();
      should((await result.unwrapErr()).code).equal('unavailable');
    }
    should(dispatches).equal(0);
    should(isPublicDeliveryAddress('93.184.216.34')).be.true();
    should(isPublicDeliveryAddress('2606:4700:4700::1111')).be.true();
  });

  it('should re-resolve every external connection and refuse a DNS rebind before dispatch', async () => {
    // Arrange
    let resolutions = 0;
    const pinned: string[] = [];
    const subject = new FetchDeliveryTransport(
      fetch,
      1_000,
      async () => {
        resolutions += 1;
        return resolutions === 1 ? [{ address: '93.184.216.34', family: 4 }] : [{ address: '127.0.0.1', family: 4 }];
      },
      async (_request, destination) => {
        pinned.push(`${destination.hostname}:${destination.address}`);
        return { status: 200, headers: {} };
      },
    );
    const request = withDeliveryAddressKind(
      { url: 'https://receiver.example/webhook', headers: {}, body: new Uint8Array() },
      'external',
    );

    // Act
    const first = await subject.send(request);
    const rebound = await subject.send(request);

    // Assert
    should(await first.isOk()).be.true();
    should(await rebound.isErr()).be.true();
    should((await rebound.unwrapErr()).code).equal('unavailable');
    should(resolutions).equal(2);
    should(pinned).deepEqual(['receiver.example:93.184.216.34']);
  });

  it('should reject an answer set containing both public and private addresses', async () => {
    // Arrange
    let dispatched = false;
    const subject = new FetchDeliveryTransport(
      fetch,
      1_000,
      async () => [
        { address: '93.184.216.34', family: 4 },
        { address: '169.254.169.254', family: 4 },
      ],
      async () => {
        dispatched = true;
        return { status: 200, headers: {} };
      },
    );

    // Act
    const result = await subject.send(
      withDeliveryAddressKind(
        { url: 'https://receiver.example/webhook', headers: {}, body: new Uint8Array() },
        'external',
      ),
    );

    // Assert
    should(await result.isErr()).be.true();
    should((await result.unwrapErr()).code).equal('unavailable');
    should(dispatched).be.false();
  });
});
