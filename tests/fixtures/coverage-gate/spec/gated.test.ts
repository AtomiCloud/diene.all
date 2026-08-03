import { describe, it } from 'bun:test';
import should from 'should';
import { alwaysMeasured, measuredOnlyWhileTheSuiteRuns } from '../src/gated';

// The sabotage skips one path so the fixture threshold must turn the run red.
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
