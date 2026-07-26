import { describe, it } from 'bun:test';
import should from 'should';
import { KeyedAdapterConstants } from '../../src/config/constants';
import { loadApplicationConfig } from '../../src/config/load';
import { applicationRegistry } from '../../src/config/schema';

const requiredAuth = {
  ATOMI_AUTH__LOGTO__APP_ID: 'consumer',
  ATOMI_AUTH__LOGTO__APP_SECRET: 'secret',
  ATOMI_AUTH__LOGTO__MANAGEMENT__CLIENT_ID: 'consumer-management',
  ATOMI_AUTH__LOGTO__MANAGEMENT__CLIENT_SECRET: 'secret',
};

describe('application config', () => {
  it('should load base, landscape overlay, and environment override in order', async () => {
    // Arrange
    const environment = { ...requiredAuth, ATOMI_TRANSPORT__CONSUMER_NAME: 'unit-override' };

    // Act
    const actual = await loadApplicationConfig({ configDir: 'config', environment, prefix: 'ATOMI_' });

    // Assert
    should(actual.transport.consumerName).equal('unit-override');
    should(actual.otel.metrics.exporter.otlp.enabled).equal(true);
  });

  it('should treat a blank runtime value as unset over a build-time value', async () => {
    // Arrange
    const buildTimeEnv = { ...requiredAuth, ATOMI_TRANSPORT__CONSUMER_NAME: 'build-time' };
    const environment = { ATOMI_TRANSPORT__CONSUMER_NAME: '' };

    // Act
    const actual = await loadApplicationConfig({ buildTimeEnv, configDir: 'config', environment, prefix: 'ATOMI_' });

    // Assert
    should(actual.transport.consumerName).equal('build-time');
  });

  it('should reject a lowercase keyed adapter name', () => {
    // Arrange
    const invalid = { postgres: { main: {} } };

    // Act
    const actual = applicationRegistry.rootSchema().safeParse(invalid);

    // Assert
    should(actual.success).equal(false);
  });

  it('should keep typed constants synchronized with every configured key', () => {
    // Arrange
    const expected = {
      cache: ['MAIN'],
      kv: ['MAIN'],
      postgres: ['MAIN'],
      storage: ['ARCHIVE', 'MAIN'],
    };

    // Act
    const actual = KeyedAdapterConstants;

    // Assert
    should(actual).deepEqual(expected);
  });
});
