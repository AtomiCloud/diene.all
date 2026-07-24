import { describe, it } from 'bun:test';
import should from 'should';
import { z } from 'zod';
import {
  buildProblemTypeUri,
  createProblem,
  type ErrorPortalConfig,
  ProblemRegistry,
  ProblemRegistryError,
} from '../../src/index.js';

const portal: ErrorPortalConfig = {
  scheme: 'https',
  host: 'errors.atomi.cloud',
  landscape: 'raichu',
  platform: 'nitroso',
  service: 'zinc',
  module: 'api',
};

describe('problem type URI', () => {
  it('should include every ErrorPortal segment and the contract version', () => {
    // Arrange
    const expected = 'https://errors.atomi.cloud/docs/raichu/nitroso/zinc/api/v7/entity_not_found';

    // Act
    const actual = buildProblemTypeUri(portal, 'v7', 'entity_not_found');

    // Assert
    should(actual).equal(expected);
  });

  it('should reject an invalid authority or contract segment', () => {
    // Arrange
    const invalidHosts = [
      '',
      'https://errors.atomi.cloud/path',
      'user@errors.atomi.cloud',
      'errors.atomi.cloud?source=test',
      'errors.atomi.cloud#fragment',
      'errors.atomi.cloud:99999',
      'ERRORS.atomi.cloud',
    ];

    // Act
    const hostErrors = invalidHosts.map(host => {
      try {
        return buildProblemTypeUri({ ...portal, host }, 'v1', 'entity_not_found');
      } catch (error: unknown) {
        return error;
      }
    });
    const segmentError = (() => {
      try {
        buildProblemTypeUri(portal, '1', 'EntityNotFound');
      } catch (error: unknown) {
        return error;
      }
    })();

    // Assert
    should(hostErrors).have.length(invalidHosts.length);
    for (const error of hostErrors) {
      should(error).be.instanceof(RangeError);
    }
    should(segmentError).be.instanceof(RangeError);
  });
});

describe('ProblemRegistry', () => {
  it('should bind definitions, sort enumeration, and mint schema-valid Problems', () => {
    // Arrange
    const registry = new ProblemRegistry(portal);
    const later = registry.register({
      id: 'validation_error',
      title: 'Validation Error',
      status: 400,
      version: 'v2',
      dataSchema: z.object({ issue: z.string() }),
    });
    const entry = registry.register({
      id: 'entity_not_found',
      title: 'Entity Not Found',
      status: 404,
      version: 'v1',
      dataSchema: z.object({ id: z.string() }),
    });
    const nextVersion = registry.register({
      id: 'entity_not_found',
      title: 'Entity Not Found',
      status: 404,
      version: 'v2',
      dataSchema: z.object({ id: z.string(), entityType: z.string() }),
    });

    // Act
    const problem = createProblem(entry, {
      detail: 'Note 42 does not exist',
      instance: '/notes/42',
      data: { id: '42' },
    });
    const invalidOverride = (() => {
      try {
        createProblem(entry, { status: 600, data: { id: '42' } });
      } catch (error: unknown) {
        return error;
      }
    })();

    // Assert
    should(registry.get(entry.id, entry.version)).equal(entry);
    should(registry.list()).eql([entry, nextVersion, later]);
    should(problem).eql({
      type: 'https://errors.atomi.cloud/docs/raichu/nitroso/zinc/api/v1/entity_not_found',
      title: 'Entity Not Found',
      status: 404,
      detail: 'Note 42 does not exist',
      instance: '/notes/42',
      data: { id: '42' },
    });
    should(invalidOverride).be.instanceof(ProblemRegistryError);
    should((invalidOverride as ProblemRegistryError).code).equal('invalid');
  });

  it('should return Result failures and throw precise registry errors', async () => {
    // Arrange
    const registry = new ProblemRegistry(portal);
    const definition = {
      id: 'unauthorized',
      title: 'Unauthorized',
      status: 401,
      version: 'v1',
      dataSchema: z.object({}),
    };

    // Act
    const first = registry.tryRegister(definition);
    const duplicate = registry.tryRegister(definition);
    const invalidStatus = registry.tryRegister({ ...definition, id: 'bad_status', status: 99 });
    const invalidTitle = registry.tryRegister({ ...definition, id: 'bad_title', title: ' ' });
    const invalidId = registry.tryRegister({ ...definition, id: 'BadId' });
    const unknown = (() => {
      try {
        registry.require('missing');
      } catch (error: unknown) {
        return error;
      }
    })();
    const ambiguous = (() => {
      try {
        const versionedRegistry = new ProblemRegistry(portal);
        versionedRegistry.register(definition);
        versionedRegistry.register({ ...definition, version: 'v2' });
        versionedRegistry.get(definition.id);
      } catch (error: unknown) {
        return error;
      }
    })();

    // Assert
    should(await first.isOk()).be.true();
    should((await duplicate.unwrapErr()).code).equal('duplicate');
    should((await invalidStatus.unwrapErr()).code).equal('invalid');
    should((await invalidTitle.unwrapErr()).code).equal('invalid');
    should((await invalidId.unwrapErr()).code).equal('invalid');
    should(unknown).be.instanceof(ProblemRegistryError);
    should((unknown as ProblemRegistryError).code).equal('unknown');
    should(ambiguous).be.instanceof(ProblemRegistryError);
    should((ambiguous as ProblemRegistryError).code).equal('invalid');
  });
});
