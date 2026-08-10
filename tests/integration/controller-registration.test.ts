import { describe, expect, it } from 'bun:test';
import { createProgram, registerDomain } from '../../bin/releaser';
import {
  captureIo,
  FakeClock,
  FakeConfigRepository,
  FakeGit,
  FakeGitHub,
  FakeHookRunner,
  loadedConfig,
  MemoryFileSystem,
} from '../helpers/fakes';

describe('controller registration', () => {
  it('should register exactly the six public commands', () => {
    // Arrange
    const program = createProgram();
    const files = new MemoryFileSystem();

    // Act
    registerDomain(program, {
      io: captureIo(),
      files,
      configs: new FakeConfigRepository(loadedConfig()),
      git: new FakeGit(),
      hooks: new FakeHookRunner(),
      github: new FakeGitHub(),
      clock: new FakeClock(),
    });

    // Assert
    expect(program.commands.map(command => command.name())).toEqual([
      'release',
      'lint-commit',
      'next',
      'changelog',
      'conventions',
      'migrate',
    ]);
  });
});
