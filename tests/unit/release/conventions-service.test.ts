import { describe, expect, it } from 'bun:test';
import { ConventionsService } from '../../../src/lib/release/conventions-service';
import { TEST_CONFIG } from '../../helpers/fakes';

describe('conventions service', () => {
  const subject = new ConventionsService();

  it.each(['CONVENTION_DOCS_PLACEHOLDER', 'var___convention_docs___'])('should replace the %s marker', marker => {
    // Arrange
    const config = { ...TEST_CONFIG, conventions: { ...TEST_CONFIG.conventions, template: `# Title\n\n${marker}` } };

    // Act
    const actual = subject.render(config);

    // Assert
    expect(actual).toContain('## Types');
    expect(actual).toContain('## Scopes');
    expect(actual).toContain('## Special scopes');
    expect(actual).toContain('## V.A.E. guidance');
    expect(actual).not.toContain(marker);
  });

  it('should reject a template without a supported marker', () => {
    const config = { ...TEST_CONFIG, conventions: { ...TEST_CONFIG.conventions, template: '# No marker' } };
    expect(() => subject.render(config)).toThrow('must contain');
  });
});
