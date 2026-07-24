import { describe, it } from 'bun:test';
import should from 'should';
import { z } from 'zod';
import { ConfigRegistry, ConfigRegistryError } from '../../src/lib/registry.js';

describe('ConfigRegistry', () => {
  it('should start empty and register blocks immutably', () => {
    // Arrange
    const empty = ConfigRegistry.create();

    // Act
    const registry = empty.register('server', z.object({ port: z.number() }));

    // Assert
    should(empty.keys).deepEqual([]);
    should(registry.keys).deepEqual(['server']);
  });

  it('should compose a root schema of every registered block', () => {
    // Arrange
    const registry = ConfigRegistry.create()
      .register('server', z.object({ port: z.number() }))
      .register('client', z.object({ name: z.string() }));

    // Act
    const parsed = registry.rootSchema().parse({ server: { port: 8080 }, client: { name: 'app' } });

    // Assert
    should(parsed).deepEqual({ server: { port: 8080 }, client: { name: 'app' } });
  });

  it('should throw ConfigRegistryError on a duplicate key', () => {
    // Arrange
    const registry = ConfigRegistry.create().register('server', z.object({ port: z.number() }));

    // Act
    const actual = () => registry.register('server', z.object({ host: z.string() }));

    // Assert
    should(actual).throw(ConfigRegistryError, { message: 'config block "server" is already registered' });
  });
});
