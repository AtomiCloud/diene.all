import { describe, expect, it } from 'bun:test';
import should from 'should';
import {
  createGenericProblemRegistry,
  EntityNotFound,
  type ErrorPortalConfig,
  emitProblemManifest,
  emitProblemResource,
  ProblemCatalog,
  ProblemRegistry,
  ProblemRegistryError,
  problemDataJsonSchema,
  registerGenericProblems,
} from '../../src/index.js';

const portal: ErrorPortalConfig = {
  scheme: 'https',
  host: 'errors.atomi.cloud',
  landscape: 'raichu',
  platform: 'nitroso',
  service: 'zinc',
  module: 'api',
};

describe('registry publication', () => {
  it('should snapshot the enumerable list and a schema keyed by every versioned type URI', () => {
    // Arrange
    const registry = createGenericProblemRegistry(portal);

    // Act
    const manifest = emitProblemManifest(registry);

    // Assert
    should(manifest.problems).have.length(3);
    should(Object.keys(manifest.schemas)).have.length(3);
    expect(manifest).toMatchSnapshot();
  });
});

describe('Problem catalog export', () => {
  it('should emit generic and service declarations as one canonical Problem row CR', () => {
    // Arrange
    const registry = createGenericProblemRegistry(portal);
    const catalog = new ProblemCatalog(registry);
    catalog.declare(registry.require('validation_error'), {
      recoverable: true,
      endpoints: [{ method: 'POST', path: '/notes' }],
    });
    catalog.declare(registry.require('entity_not_found'), {
      recoverable: false,
      endpoints: [{ method: 'GET', path: '/notes/{id}' }],
    });
    catalog.declare(registry.require('unauthorized'), {
      recoverable: true,
      endpoints: [{ method: 'GET', path: '/notes' }],
    });

    // Act
    const resource = emitProblemResource(catalog, {
      platform: 'nitroso',
      service: 'zinc',
      landscape: 'raichu',
      version: 'v1',
    });

    // Assert
    should(resource.spec.problems).have.length(3);
    should(resource.spec.problems[0]).have.property('schema');
    should(resource.spec.problems[0]).not.have.property('data');
    expect(resource).toMatchSnapshot();
  });

  it('should reject invalid endpoints, duplicate declarations, foreign entries, and row drift', () => {
    // Arrange
    const registry = new ProblemRegistry(portal);
    const entries = registerGenericProblems(registry);
    const catalog = new ProblemCatalog(registry);
    const declared = catalog.declare(
      {
        ...entries.EntityNotFound,
        title: 'Forged title',
        status: 599,
        dataSchema: entries.Unauthorized.dataSchema,
      },
      {
        recoverable: false,
        endpoints: [{ method: 'GET', path: '/notes/{id}' }],
      },
    );
    const resourceWithIgnoredNamespace = emitProblemResource(catalog, {
      platform: 'nitroso',
      service: 'zinc',
      landscape: 'raichu',
      version: 'v1',
      namespace: 'forged',
    } as Parameters<typeof emitProblemResource>[1] & { namespace: string });
    const declaration = {
      recoverable: false,
      endpoints: [{ method: 'GET', path: '/notes/{id}' }],
    };
    const foreignRegistry = new ProblemRegistry({ ...portal, service: 'argon' });
    const foreign = foreignRegistry.register({ ...EntityNotFound, version: 'v1' });
    const capture = (action: () => unknown): unknown => {
      try {
        return action();
      } catch (error: unknown) {
        return error;
      }
    };

    // Act
    const duplicate = capture(() => catalog.declare(entries.EntityNotFound, declaration));
    const foreignError = capture(() =>
      catalog.declare(foreign, { recoverable: false, endpoints: [{ method: 'GET', path: '/notes/{id}' }] }),
    );
    const methodError = capture(() =>
      new ProblemCatalog(registry).declare(entries.ValidationError, {
        recoverable: true,
        endpoints: [{ method: 'post', path: '/notes' }],
      }),
    );
    const pathError = capture(() =>
      new ProblemCatalog(registry).declare(entries.Unauthorized, {
        recoverable: true,
        endpoints: [{ method: 'GET', path: 'notes' }],
      }),
    );
    const identityError = capture(() =>
      emitProblemResource(catalog, {
        platform: 'other',
        service: 'zinc',
        landscape: 'raichu',
        version: 'v1',
      }),
    );
    const versionError = capture(() =>
      emitProblemResource(catalog, {
        platform: 'nitroso',
        service: 'zinc',
        landscape: 'raichu',
        version: 'v2',
      }),
    );

    // Assert
    should(duplicate).be.instanceof(ProblemRegistryError);
    should(declared.title).equal(entries.EntityNotFound.title);
    should(declared.status).equal(entries.EntityNotFound.status);
    should(declared.data).eql(problemDataJsonSchema(entries.EntityNotFound));
    should(resourceWithIgnoredNamespace.metadata.namespace).equal('nitroso');
    should(foreignError).be.instanceof(ProblemRegistryError);
    should(methodError).be.instanceof(RangeError);
    should(pathError).be.instanceof(RangeError);
    should(identityError).be.instanceof(RangeError);
    should(versionError).be.instanceof(RangeError);
  });
});
