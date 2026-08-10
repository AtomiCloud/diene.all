import { describe, it } from 'bun:test';
import should from 'should';
import { themeCssVariables } from '../../src/lib/tokens';

describe('themeCssVariables', () => {
  it('should ship light and dark themes with identical variable sets', () => {
    // Arrange
    const light = Object.keys(themeCssVariables['light'] ?? {}).sort();
    const dark = Object.keys(themeCssVariables['dark'] ?? {}).sort();

    // Act & Assert
    should(light).deepEqual(dark);
    should(light.length).be.greaterThan(0);
  });

  it('should not ship a default-grey primary (identity scaffold doctrine)', () => {
    // Arrange
    const lightPrimary = themeCssVariables['light']?.['--primary'] ?? '';

    // Act — a grey value in oklch has zero chroma (second component 0).
    const chroma = Number(lightPrimary.match(/oklch\([\d.]+ ([\d.]+) /)?.[1] ?? '0');

    // Assert
    should(chroma).be.greaterThan(0.05);
  });
});
