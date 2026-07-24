import type { Result } from '@atomicloud/diene.result';
import { portError, type TerminalError } from './error.js';
import { accepted, type Checked, rejected, resultFromChecked } from './validation.js';

type TerminalChannel = 'stderr' | 'stdout';

interface TerminalWrite {
  readonly channel: TerminalChannel;
  readonly text: string;
  readonly newline?: boolean;
}

interface TerminalRead {
  readonly prompt?: string;
}

interface Terminal {
  readonly interactive: boolean;
  write(output: TerminalWrite): Result<void, TerminalError>;
  readLine(input?: TerminalRead): Result<string | null, TerminalError>;
}

function invalidTerminalInput(operation: string, field: string, message: string): Checked<never, TerminalError> {
  return rejected(portError('terminal', 'invalid-input', operation, message, { field }));
}

function checkTerminalWrite(output: TerminalWrite): Checked<Required<TerminalWrite>, TerminalError> {
  if (typeof output !== 'object' || output === null) {
    return invalidTerminalInput('write', 'output', 'Terminal output must be an object');
  }
  if (output.channel !== 'stdout' && output.channel !== 'stderr') {
    return invalidTerminalInput('write', 'channel', 'Terminal channel must be stdout or stderr');
  }
  if (typeof output.text !== 'string') {
    return invalidTerminalInput('write', 'text', 'Terminal text must be a string');
  }
  if (output.newline !== undefined && typeof output.newline !== 'boolean') {
    return invalidTerminalInput('write', 'newline', 'Terminal newline must be a boolean');
  }
  return accepted(Object.freeze({ channel: output.channel, text: output.text, newline: output.newline ?? false }));
}

function checkTerminalRead(input: TerminalRead = {}): Checked<Readonly<TerminalRead>, TerminalError> {
  if (
    typeof input !== 'object' ||
    input === null ||
    Array.isArray(input) ||
    ![Object.prototype, null].includes(Object.getPrototypeOf(input))
  ) {
    return invalidTerminalInput('readLine', 'input', 'Terminal input must be an object');
  }
  if (input.prompt !== undefined && typeof input.prompt !== 'string') {
    return invalidTerminalInput('readLine', 'prompt', 'Terminal prompt must be a string');
  }
  return accepted(Object.freeze(input.prompt === undefined ? {} : { prompt: input.prompt }));
}

function validateTerminalWrite(output: TerminalWrite): Result<Required<TerminalWrite>, TerminalError> {
  return resultFromChecked(checkTerminalWrite(output));
}

function validateTerminalRead(input: TerminalRead = {}): Result<Readonly<TerminalRead>, TerminalError> {
  return resultFromChecked(checkTerminalRead(input));
}

export type { Terminal, TerminalChannel, TerminalRead, TerminalWrite };
export { checkTerminalRead, checkTerminalWrite, validateTerminalRead, validateTerminalWrite };
