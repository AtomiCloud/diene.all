import { describe, it } from 'bun:test';
import should from 'should';
import { isHostAllowed, validateEndpoint } from '@atomicloud/diene.frontend-utils/discovery';
import { pickerAllowlist, pickerPingRoot } from '../../src/lib/allowlist';
import type { PickerConfig } from '../../src/config';

// The BAKED endpoint-suffix allowlist replaces doc signing, so its derivation
// from picker config is the security boundary: an accept/reject table proves a
// doc-sourced URL outside the suffix can never be used.

const picker: PickerConfig = {
  docBUrl: 'https://edge.cluster.atomi.cloud/docs/doc-b.json',
  allowedSuffixes: ['.cluster.atomi.cloud'],
  pingTimeoutMs: 2000,
};

describe('pickerAllowlist', () => {
  it('should carry the configured suffixes and grant no rescue roots', () => {
    // Arrange

    // Act
    const actual = pickerAllowlist(picker);

    // Assert
    should(actual.suffixes).deepEqual(['.cluster.atomi.cloud']);
    should(actual.rescueRoots).deepEqual([]);
  });

  it('should drop a blank suffix so it can never match every host', () => {
    // Arrange
    const permissive: PickerConfig = { ...picker, allowedSuffixes: ['.cluster.atomi.cloud', '', '   '] };

    // Act
    const actual = pickerAllowlist(permissive);

    // Assert
    should(actual.suffixes).deepEqual(['.cluster.atomi.cloud']);
  });

  it.each([
    { host: 'ping.lapras.cluster.atomi.cloud', expected: true },
    { host: 'edge.cluster.atomi.cloud', expected: true },
    { host: 'evil.example.com', expected: false },
    { host: 'cluster.atomi.cloud.evil.com', expected: false },
    { host: 'notcluster.atomi.cloud', expected: false },
    { host: 'rescue.atomi.cloud', expected: false },
  ])('should resolve host $host to allowed=$expected', ({ host, expected }) => {
    // Arrange
    const config = pickerAllowlist(picker);

    // Act
    const actual = isHostAllowed(host, config);

    // Assert
    should(actual).equal(expected);
  });

  it('should reject every host when no usable suffix survives', () => {
    // Arrange
    const blank: PickerConfig = { ...picker, allowedSuffixes: ['   '] };

    // Act
    const actual = isHostAllowed('ping.lapras.cluster.atomi.cloud', pickerAllowlist(blank));

    // Assert
    should(actual).equal(false);
  });

  it('should accept the configured Doc B URL through validateEndpoint', async () => {
    // Arrange
    const config = pickerAllowlist(picker);

    // Act
    const actual = await validateEndpoint(picker.docBUrl, config).serial();

    // Assert
    should(actual[0]).equal('ok');
  });

  it.each([
    { label: 'a host outside the allowlist', url: 'https://evil.example.com/doc-b.json' },
    { label: 'a non-HTTPS scheme', url: 'http://edge.cluster.atomi.cloud/doc-b.json' },
    { label: 'an unparseable URL', url: 'not-a-url' },
  ])('should reject $label through validateEndpoint', async ({ url }) => {
    // Arrange
    const config = pickerAllowlist(picker);

    // Act
    const actual = await validateEndpoint(url, config).serial();

    // Assert
    should(actual[0]).equal('err');
  });
});

describe('pickerPingRoot', () => {
  it('should strip the leading dot from the first allowed suffix', () => {
    // Arrange

    // Act
    const actual = pickerPingRoot(picker);

    // Assert
    should(actual).equal('cluster.atomi.cloud');
  });

  it('should fall back to the cluster root when no suffix is configured', () => {
    // Arrange
    const empty = { ...picker, allowedSuffixes: [] as unknown as PickerConfig['allowedSuffixes'] };

    // Act
    const actual = pickerPingRoot(empty);

    // Assert
    should(actual).equal('cluster.atomi.cloud');
  });
});
