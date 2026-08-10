import {
  PortError,
  portError,
  type LoggerSink,
  type MetricsCollector,
  type System,
  type Terminal,
  type VfsError,
  type VirtualFileSystem,
} from '@atomicloud/diene.interfaces';
import {
  InMemoryLoggerSink,
  InMemoryMetricsCollector,
  InMemorySystem,
  InMemoryTerminal,
  InMemoryVirtualFileSystem,
  type VfsCall,
} from '@atomicloud/diene.interfaces/test-helper';

// Root entry: types and the PortError value resolve through the import condition.
const failure: PortError<'vfs'> = portError('vfs', 'not-found', 'readFile', 'node16-esm');
const asError: VfsError = failure;

// test-helper entry: the in-memory doubles satisfy the root port contracts.
const system: System = new InMemorySystem();
const vfs: VirtualFileSystem = new InMemoryVirtualFileSystem();
const terminal: Terminal = new InMemoryTerminal();
const logger: LoggerSink = new InMemoryLoggerSink();
const metrics: MetricsCollector = new InMemoryMetricsCollector();
const recordedCalls: readonly VfsCall[] = new InMemoryVirtualFileSystem().calls;

void [asError, system, vfs, terminal, logger, metrics, recordedCalls];
