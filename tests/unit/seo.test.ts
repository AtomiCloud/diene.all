import { describe, it } from 'bun:test';
import should from 'should';
import { absoluteUrl, organizationJsonLd } from '../../src/lib/seo';

const seo = {
  baseUrl: 'https://webapp.test.example',
  titleTemplate: '%s · Test',
  defaultTitle: 'Test',
  defaultDescription: 'Test app',
  ogImage: '/og.png',
  twitterCard: 'summary' as const,
  twitterSite: '',
  jsonLdOrganization: { name: 'Acme', url: 'https://acme.example', logo: '/logo.png' },
};

describe('organizationJsonLd', () => {
  it('should emit a schema.org Organization from config', () => {
    // Arrange

    // Act
    const actual = organizationJsonLd(seo);

    // Assert
    should(actual['@type']).equal('Organization');
    should(actual.name).equal('Acme');
    should(actual.url).equal('https://acme.example');
  });
});

describe('absoluteUrl', () => {
  it.each([
    { path: '/about', expected: 'https://webapp.test.example/about' },
    { path: 'og.png', expected: 'https://webapp.test.example/og.png' },
  ])('should absolutize "$path"', ({ path, expected }) => {
    // Arrange

    // Act
    const actual = absoluteUrl(seo, path);

    // Assert
    should(actual).equal(expected);
  });
});
