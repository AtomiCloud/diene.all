import { describe, it } from 'bun:test';
import should from 'should';
import { z } from 'zod';
import { ConfigRegistry } from '../../src/lib/registry.js';
import { generateJsonSchema } from '../../src/lib/schema.js';

const registry = ConfigRegistry.create()
  .register('server', z.object({ port: z.number(), host: z.string() }))
  .register('client', z.object({ name: z.string() }));

describe('generateJsonSchema', () => {
  it('should emit a JSON schema describing every registered block', () => {
    // Arrange

    // Act
    const actual = generateJsonSchema(registry) as {
      type: string;
      properties: Record<string, unknown>;
      required?: string[];
    };

    // Assert
    should(actual.type).equal('object');
    should(Object.keys(actual.properties)).containDeep(['server', 'client']);
  });

  it('should validate the sample config with a real JSON-schema/zod round-trip', () => {
    // Arrange
    const good = { server: { port: 8080, host: 'localhost' }, client: { name: 'app' } };
    const bad = { server: { port: 'x', host: 'localhost' }, client: { name: 'app' } };

    // Act
    const okParsed = registry.rootSchema().safeParse(good);
    const badParsed = registry.rootSchema().safeParse(bad);

    // Assert
    should(okParsed.success).be.true();
    should(badParsed.success).be.false();
  });

  it('should stamp an optional $id when provided', () => {
    // Arrange

    // Act
    const actual = generateJsonSchema(registry, { id: 'https://atomi/config.json' }) as { $id?: string };

    // Assert
    should(actual.$id).equal('https://atomi/config.json');
  });
});
