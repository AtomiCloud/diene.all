import { describe, it } from 'bun:test';
import should from 'should';
import {
  createGenericProblemRegistry,
  createProblem,
  type ErrorPortalConfig,
  ProblemRegistryError,
} from '../../src/index.js';
import {
  buildProblem,
  buildProblemFromRegistry,
  expectProblem,
  ProblemAssertionError,
} from '../../src/test-helper/index.js';

const portal: ErrorPortalConfig = {
  scheme: 'https',
  host: 'errors.atomi.cloud',
  landscape: 'raichu',
  platform: 'nitroso',
  service: 'zinc',
  module: 'api',
};

describe('Problem TestHelper', () => {
  it('should build schema-valid Problems and return a typed successful assertion', () => {
    // Arrange
    const registry = createGenericProblemRegistry(portal);
    const expected = registry.require('entity_not_found');
    const actual = buildProblem(expected, {
      detail: 'missing',
      instance: '/notes/42',
      data: { entityType: 'Note', id: '42' },
    });

    // Act
    const asserted = expectProblem(actual).toBe(expected, {
      detail: 'missing',
      instance: '/notes/42',
      data: { id: '42', entityType: 'Note' },
    });
    const fromRegistry = buildProblemFromRegistry(registry, 'unauthorized', { data: {} }, 'v1');

    // Assert
    should(asserted).equal(actual);
    should(fromRegistry.status).equal(401);
  });

  it('should fail on every mismatched registry field and invalid data shape', () => {
    // Arrange
    const registry = createGenericProblemRegistry(portal);
    const expected = registry.require('entity_not_found');
    const actual = {
      type: 'https://wrong.example/problem',
      title: 'Wrong',
      status: 500,
      detail: 'wrong detail',
      instance: '/wrong',
      data: { unknown: true },
    };

    // Act
    const assertion = (() => {
      try {
        expectProblem(actual).toBe(expected, {
          status: 409,
          detail: 'expected detail',
          instance: '/expected',
          data: { entityType: 'Note', id: '42' },
        });
      } catch (error: unknown) {
        return error;
      }
    })();

    // Assert
    should(assertion).be.instanceof(ProblemAssertionError);
    should((assertion as ProblemAssertionError).differences).have.length(7);
    should((assertion as Error).message).startWith('Problem assertion failed:\n- type expected');
  });

  it('should render non-JSON assertion payloads and expose unknown registry ids', () => {
    // Arrange
    const registry = createGenericProblemRegistry(portal);
    const expected = registry.require('unauthorized');
    const circular: { self?: unknown } = {};
    circular.self = circular;
    const actual = createProblem(expected, { data: {} });
    const withCircular = { ...actual, data: circular };

    // Act
    const assertion = (() => {
      try {
        expectProblem(withCircular).toBe(expected, { data: {} });
      } catch (error: unknown) {
        return error;
      }
    })();
    const unknown = (() => {
      try {
        buildProblemFromRegistry(registry, 'missing', { data: {} });
      } catch (error: unknown) {
        return error;
      }
    })();

    // Assert
    should(assertion).be.instanceof(ProblemAssertionError);
    should(unknown).be.instanceof(ProblemRegistryError);
  });

  it('should compare schema-valid data exactly while leaving omitted optional fields unconstrained', () => {
    // Arrange
    const registry = createGenericProblemRegistry(portal);
    const expected = registry.require('entity_not_found');
    const actual = createProblem(expected, {
      detail: 'present but not asserted',
      instance: '/notes/42',
      data: { entityType: 'Note', id: '42' },
    });

    // Act
    const omittedFields = expectProblem(actual).toBe(expected);
    const dataMismatch = (() => {
      try {
        expectProblem(actual).toBe(expected, { data: { entityType: 'Note', id: '43' } });
      } catch (error: unknown) {
        return error;
      }
    })();

    // Assert
    should(omittedFields).equal(actual);
    should(dataMismatch).be.instanceof(ProblemAssertionError);
    should((dataMismatch as ProblemAssertionError).differences).eql([
      'data expected {\n  "entityType": "Note",\n  "id": "43"\n}, received {\n  "entityType": "Note",\n  "id": "42"\n}',
    ]);
  });
});
