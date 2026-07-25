import { describe, it } from 'bun:test';
import should from 'should';
import { FARO_ATTR_KEYS, faroApp, faroAttrs } from '../../src/lib/faro-attrs';
import type { ClientSafeConfig } from '../../src/config';

// Every Faro signal must carry the full LPSM coordinate, and landscape must be
// the SSR-injected one (server tells client) — never a build-time constant.

const clientConfig = (landscape: string): ClientSafeConfig =>
  ({
    landscape,
    app: {
      servicetree: { landscape: 'base', platform: 'diene', service: 'nextjs-frontend', module: 'webapp' },
    },
    faro: { enabled: true, endpoint: 'https://faro.example.com/collect', app: 'webapp.nextjs-frontend.base' },
  }) as unknown as ClientSafeConfig;

describe('faroAttrs', () => {
  it('should carry every LPSM slot', () => {
    // Arrange
    const config = clientConfig('pichu');

    // Act
    const actual = faroAttrs(config);

    // Assert
    should(actual).deepEqual({
      landscape: 'pichu',
      platform: 'diene',
      service: 'nextjs-frontend',
      module: 'webapp',
    });
  });

  it.each([...FARO_ATTR_KEYS])('should expose a non-empty %s attribute', key => {
    // Arrange
    const config = clientConfig('raichu');

    // Act
    const actual = faroAttrs(config);

    // Assert
    should(Object.keys(actual)).containEql(key);
    should(actual[key].length).be.above(0);
  });

  it('should take landscape from the SSR payload, not the baked servicetree block', () => {
    // Arrange — the baked block says `base`; the payload says `pikachu`.
    const config = clientConfig('pikachu');

    // Act
    const actual = faroAttrs(config);

    // Assert
    should(actual.landscape).equal('pikachu');
  });
});

describe('faroApp', () => {
  it('should build the app descriptor with the configured name and reported landscape', () => {
    // Arrange
    const config = clientConfig('pichu');

    // Act
    const actual = faroApp(config, '1.2.3');

    // Assert
    should(actual).deepEqual({
      name: 'webapp.nextjs-frontend.base',
      version: '1.2.3',
      environment: 'pichu',
    });
  });
});
