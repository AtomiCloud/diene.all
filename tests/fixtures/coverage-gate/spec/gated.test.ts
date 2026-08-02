import { describe, it } from 'bun:test';
import should from 'should';
import { alwaysMeasured, measuredOnlyWhileTheSuiteRuns } from '../src/gated';

// Flipping this variable is the sabotage: the gated test stops running, its function stops being
// covered, and the fixture's 100% threshold must turn that into a non-zero exit.
const sabotaged = process.env.COVERAGE_GATE_SABOTAGE === '1';
const gated = sabotaged ? it.skip : it;

describe('coverage gate fixture', () => {
  it('should cover the baseline function in every run', () => {
    // Arrange
    const input = 1;
    const expected = 2;

    // Act
    const actual = alwaysMeasured(input);

    // Assert
    should(actual).equal(expected);
  });

  gated('should cover the gated function unless the run is sabotaged', () => {
    // Arrange
    const input = 2;
    const expected = 4;

    // Act
    const actual = measuredOnlyWhileTheSuiteRuns(input);

    // Assert
    should(actual).equal(expected);
  });
});
