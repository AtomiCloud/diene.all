import { describe, it } from 'bun:test';
import should from 'should';
import { authEngineConfigSchema } from '../../src/lib/config';

const input = {
  logto: {
    endpoint: 'https://identity.invalid',
    appId: 'app',
    appSecret: 'injected-app-secret',
    management: {
      endpoint: 'https://management.invalid',
      clientId: 'm2m',
      clientSecret: 'injected-management-secret',
    },
  },
  handoff: {},
  store: { kind: 'redis', host: 'redis.invalid', port: 6379 },
};

describe('authEngineConfigSchema', () => {
  it('validates final injected config and applies the contract mount default', () => {
    // Arrange
    const candidate = input;

    // Act
    const actual = authEngineConfigSchema.safeParse(candidate);

    // Assert
    actual.success.should.be.true();
    if (!actual.success) return;
    actual.data.handoff.mount.should.equal('/app-handoff');
    actual.data.logto.appSecret.should.equal('injected-app-secret');
  });

  it('preserves significant whitespace in injected opaque secrets', () => {
    // Arrange
    const candidate = {
      ...input,
      logto: {
        ...input.logto,
        appSecret: ' app secret ',
        management: { ...input.logto.management, clientSecret: '\tmanagement secret\n' },
      },
    };

    // Act
    const actual = authEngineConfigSchema.safeParse(candidate);

    // Assert
    actual.success.should.be.true();
    if (!actual.success) return;
    actual.data.logto.appSecret.should.equal(' app secret ');
    actual.data.logto.management.clientSecret.should.equal('\tmanagement secret\n');
  });

  it.each([
    { name: 'root unknown key', candidate: { ...input, unknown: true } },
    { name: 'logto unknown key', candidate: { ...input, logto: { ...input.logto, unknown: true } } },
    { name: 'handoff unknown key', candidate: { ...input, handoff: { unknown: true } } },
    { name: 'store unknown key', candidate: { ...input, store: { ...input.store, unknown: true } } },
    { name: 'blank endpoint', candidate: { ...input, logto: { ...input.logto, endpoint: '' } } },
    { name: 'non-URL endpoint', candidate: { ...input, logto: { ...input.logto, endpoint: 'identity' } } },
    {
      name: 'non-HTTP endpoint',
      candidate: { ...input, logto: { ...input.logto, endpoint: 'ftp://identity.invalid' } },
    },
    {
      name: 'endpoint with path',
      candidate: { ...input, logto: { ...input.logto, endpoint: 'https://identity.invalid/tenant' } },
    },
    {
      name: 'endpoint with credentials',
      candidate: { ...input, logto: { ...input.logto, endpoint: 'https://user:pass@identity.invalid' } },
    },
    {
      name: 'blank management endpoint',
      candidate: {
        ...input,
        logto: { ...input.logto, management: { ...input.logto.management, endpoint: '' } },
      },
    },
    {
      name: 'non-URL management endpoint',
      candidate: {
        ...input,
        logto: { ...input.logto, management: { ...input.logto.management, endpoint: 'management' } },
      },
    },
    {
      name: 'non-HTTP management endpoint',
      candidate: {
        ...input,
        logto: {
          ...input.logto,
          management: { ...input.logto.management, endpoint: 'ftp://management.invalid' },
        },
      },
    },
    {
      name: 'management endpoint with query',
      candidate: {
        ...input,
        logto: {
          ...input.logto,
          management: {
            ...input.logto.management,
            endpoint: 'https://management.invalid?tenant=argon',
          },
        },
      },
    },
    { name: 'blank app id', candidate: { ...input, logto: { ...input.logto, appId: '  ' } } },
    { name: 'blank injected app secret', candidate: { ...input, logto: { ...input.logto, appSecret: '' } } },
    {
      name: 'blank management client id',
      candidate: {
        ...input,
        logto: { ...input.logto, management: { ...input.logto.management, clientId: '' } },
      },
    },
    {
      name: 'blank injected management secret',
      candidate: {
        ...input,
        logto: { ...input.logto, management: { ...input.logto.management, clientSecret: '' } },
      },
    },
    { name: 'blank Redis host', candidate: { ...input, store: { ...input.store, host: '' } } },
    { name: 'fractional Redis port', candidate: { ...input, store: { ...input.store, port: 6379.5 } } },
    { name: 'zero Redis port', candidate: { ...input, store: { ...input.store, port: 0 } } },
    { name: 'out-of-range Redis port', candidate: { ...input, store: { ...input.store, port: 65_536 } } },
    { name: 'relative mount', candidate: { ...input, handoff: { mount: 'app-handoff' } } },
    { name: 'authority mount', candidate: { ...input, handoff: { mount: '//evil.invalid/path' } } },
    { name: 'backslash mount', candidate: { ...input, handoff: { mount: '/\\evil' } } },
    { name: 'query mount', candidate: { ...input, handoff: { mount: '/app-handoff?next=/other' } } },
    { name: 'traversal mount', candidate: { ...input, handoff: { mount: '/app/../handoff' } } },
    { name: 'encoded traversal mount', candidate: { ...input, handoff: { mount: '/%2e%2e/handoff' } } },
    { name: 'empty mount segment', candidate: { ...input, handoff: { mount: '/app//handoff' } } },
  ])('rejects $name through safeParse', ({ candidate }) => {
    // Arrange
    const untrusted = candidate;

    // Act
    const actual = authEngineConfigSchema.safeParse(untrusted);

    // Assert
    actual.success.should.be.false();
    should(actual.error).not.be.undefined();
  });
});
