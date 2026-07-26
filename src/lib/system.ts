import type { Result } from '@atomicloud/diene.result';
import { portError, type SystemError } from './error.js';
import { accepted, type Checked, rejected, resultFromChecked } from './validation.js';

interface ProcessRequest {
  readonly executable: string;
  readonly arguments?: readonly string[];
  readonly cwd?: string;
  readonly environment?: Readonly<Record<string, string>>;
  readonly stdin?: string;
  readonly timeoutMs?: number;
}

interface ProcessOutput {
  readonly exitCode: number;
  readonly stdout: string;
  readonly stderr: string;
}

interface System {
  execute(request: ProcessRequest): Result<ProcessOutput, SystemError>;
}

function invalidProcessRequest(field: string, message: string): Checked<never, SystemError> {
  return rejected(portError('system', 'invalid-input', 'execute', message, { field }));
}

function checkProcessRequest(request: ProcessRequest): Checked<ProcessRequest, SystemError> {
  if (typeof request !== 'object' || request === null) {
    return invalidProcessRequest('request', 'Process request must be an object');
  }
  if (typeof request.executable !== 'string' || request.executable.trim() === '') {
    return invalidProcessRequest('executable', 'Process executable must not be blank');
  }
  if (request.executable.includes('\0')) {
    return invalidProcessRequest('executable', 'Process executable must not contain NUL');
  }
  if (
    request.arguments !== undefined &&
    (!Array.isArray(request.arguments) ||
      Array.from(request.arguments).some(argument => typeof argument !== 'string' || argument.includes('\0')))
  ) {
    return invalidProcessRequest('arguments', 'Process arguments must be NUL-free strings');
  }
  if (
    request.cwd !== undefined &&
    (typeof request.cwd !== 'string' || request.cwd === '' || request.cwd.includes('\0'))
  ) {
    return invalidProcessRequest('cwd', 'Process cwd must be a non-empty NUL-free string');
  }
  if (
    request.environment !== undefined &&
    (typeof request.environment !== 'object' ||
      request.environment === null ||
      Array.isArray(request.environment) ||
      ![Object.prototype, null].includes(Object.getPrototypeOf(request.environment)))
  ) {
    return invalidProcessRequest('environment', 'Process environment must be a string record');
  }
  if (
    request.environment !== undefined &&
    Object.entries(request.environment).some(
      ([key, value]) =>
        key === '' || key.includes('=') || key.includes('\0') || typeof value !== 'string' || value.includes('\0'),
    )
  ) {
    return invalidProcessRequest('environment', 'Process environment entries must be valid NUL-free strings');
  }
  if (request.stdin !== undefined && typeof request.stdin !== 'string') {
    return invalidProcessRequest('stdin', 'Process stdin must be a string');
  }
  if (request.timeoutMs !== undefined && (!Number.isInteger(request.timeoutMs) || request.timeoutMs <= 0)) {
    return invalidProcessRequest('timeoutMs', 'Process timeoutMs must be a positive integer');
  }

  return accepted(
    Object.freeze({
      executable: request.executable,
      ...(request.arguments === undefined ? {} : { arguments: Object.freeze([...request.arguments]) }),
      ...(request.cwd === undefined ? {} : { cwd: request.cwd }),
      ...(request.environment === undefined ? {} : { environment: Object.freeze({ ...request.environment }) }),
      ...(request.stdin === undefined ? {} : { stdin: request.stdin }),
      ...(request.timeoutMs === undefined ? {} : { timeoutMs: request.timeoutMs }),
    }),
  );
}

function validateProcessRequest(request: ProcessRequest): Result<ProcessRequest, SystemError> {
  return resultFromChecked(checkProcessRequest(request));
}

function checkProcessOutput(output: ProcessOutput): Checked<ProcessOutput, SystemError> {
  if (
    typeof output !== 'object' ||
    output === null ||
    !Number.isInteger(output.exitCode) ||
    typeof output.stdout !== 'string' ||
    typeof output.stderr !== 'string'
  ) {
    return rejected(
      portError(
        'system',
        'invalid-input',
        'execute',
        'Process output must contain an integer exit code and text streams',
      ),
    );
  }
  return accepted(Object.freeze({ exitCode: output.exitCode, stderr: output.stderr, stdout: output.stdout }));
}

function validateProcessOutput(output: ProcessOutput): Result<ProcessOutput, SystemError> {
  return resultFromChecked(checkProcessOutput(output));
}

export type { ProcessOutput, ProcessRequest, System };
export { checkProcessOutput, checkProcessRequest, validateProcessOutput, validateProcessRequest };
