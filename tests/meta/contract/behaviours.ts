import { it } from 'bun:test';
import type { Result } from '@atomicloud/diene.result';
import 'should';
import { expectErr, expectOk } from '../support/capture';

// A single behavioural contract run against BOTH the real adapter seam and its
// in-memory mock (LSP parity, G1-bounded: in-process, no network). Each seam is
// reduced to a valid operation, a shared-validator-rejected operation, and a
// flush — the three behaviours every emit seam must agree on.

interface SeamContract {
  validOperation(): Result<void, unknown>;
  invalidOperation(): Result<void, unknown>;
  flush(): Result<void, unknown>;
}

function runSeamContract(make: () => SeamContract): void {
  it('should accept a valid operation', async () => {
    // Act / Assert
    await expectOk(make().validOperation());
  });

  it('should reject an invalid operation through the shared validator', async () => {
    // Act
    const error = await expectErr(make().invalidOperation());

    // Assert - every seam runs the shared check* validator first
    (error as { readonly code: string }).code.should.eql('invalid-input');
  });

  it('should flush successfully', async () => {
    // Act / Assert
    await expectOk(make().flush());
  });
}

export type { SeamContract };
export { runSeamContract };
