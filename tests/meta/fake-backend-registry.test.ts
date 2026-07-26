import { describe, it } from 'bun:test';
import type { Problem } from '@atomicloud/diene.problems';
import should from 'should';
import type { BackendRegistration } from '../../src/lib/resource-tree';
import { InMemoryBackendRegistry } from '../../src/test-helper';

function registration(backendId: string): BackendRegistration {
  const onboardingResource = {
    platform: 'alcohol',
    landscape: 'lapras',
    service: backendId,
    resourceName: 'onboarding',
  };
  return { backendId, resources: [onboardingResource], onboardingResource };
}

function registryProblem(): Problem {
  return {
    type: 'about:blank',
    title: 'Registry failure',
    status: 500,
    detail: 'The fake registry was instructed to fail.',
    data: {},
  };
}

describe('InMemoryBackendRegistry', () => {
  it('registers, replaces, gets, and lists backend values', async () => {
    // Arrange
    const subject = new InMemoryBackendRegistry();
    const first = registration('zinc');
    const replacement = { ...first, resources: [...first.resources] };
    const second = registration('tin');

    // Act
    const firstResult = await subject.register(first).serial();
    const replacementResult = await subject.register(replacement).serial();
    const secondResult = await subject.register(second).serial();
    const zinc = subject.get('zinc');
    const missing = subject.get('missing');
    const listed = subject.list();

    // Assert
    should(firstResult[0]).equal('ok');
    should(replacementResult[0]).equal('ok');
    should(secondResult[0]).equal('ok');
    should(zinc).equal(replacement);
    should(missing).be.undefined();
    should(listed).deepEqual([replacement, second]);
    should(subject.values.size).equal(2);
  });

  it('returns the configured Problem without mutating registry values', async () => {
    // Arrange
    const subject = new InMemoryBackendRegistry();
    const problem = registryProblem();
    subject.failure = problem;

    // Act
    const actual = await subject.register(registration('zinc')).serial();

    // Assert
    should(actual).deepEqual(['err', problem]);
    should(subject.list()).deepEqual([]);
  });
});
