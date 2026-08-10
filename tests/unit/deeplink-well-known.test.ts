import { describe, it } from 'bun:test';
import should from 'should';
import { buildAasa, buildAssetLinks } from '../../src/lib/deeplink/well-known';

const deeplink = {
  appleAppId: 'TEAM123.cloud.atomi.test.webapp',
  androidPackage: 'cloud.atomi.test.webapp',
  androidSha256Fingerprints: ['AA:BB'],
};

describe('buildAasa', () => {
  it('should carry the configured apple app id', () => {
    // Arrange
    const patterns = ['/', '/profile'];

    // Act
    const actual = buildAasa(deeplink, patterns);

    // Assert
    should(actual.applinks.details[0]?.appIDs).deepEqual(['TEAM123.cloud.atomi.test.webapp']);
  });

  it('should convert :params into wildcards', () => {
    // Arrange
    const patterns = ['/items/:id/edit'];

    // Act
    const actual = buildAasa(deeplink, patterns);

    // Assert
    should(actual.applinks.details[0]?.components[0]?.['/']).equal('/items/*/edit');
  });
});

describe('buildAssetLinks', () => {
  it('should emit the handle_all_urls relation for the configured package', () => {
    // Arrange

    // Act
    const actual = buildAssetLinks(deeplink);

    // Assert
    should(actual[0]?.relation).deepEqual(['delegate_permission/common.handle_all_urls']);
    should(actual[0]?.target.package_name).equal('cloud.atomi.test.webapp');
    should(actual[0]?.target.sha256_cert_fingerprints).deepEqual(['AA:BB']);
  });
});
