import { YamlConfigSource, loadConfig } from '@atomicloud/diene.config';
import { describe, it } from 'bun:test';
import should from 'should';
import { configRegistry } from '../../src/config';

// The config tree is ONE tree with four tiers resolved in a fixed precedence
// order: base YAML → landscape overlay → build-time env → runtime env. This
// suite pins that order against the SHIPPED config/ directory rather than a
// hand-built fixture, so a schema or overlay change cannot drift past it.

const dir = `${process.cwd()}/config`;

const load = (landscape: string, tiers?: { env?: Record<string, string>; buildTimeEnv?: Record<string, string> }) =>
  loadConfig(
    new YamlConfigSource({
      dir,
      // Empty records — never `process.env`. A test that inherited the ambient
      // environment would pass or fail on whatever the shell happened to export.
      env: tiers?.env ?? {},
      buildTimeEnv: tiers?.buildTimeEnv ?? {},
    }),
    configRegistry,
    { prefix: 'ATOMI_', landscape },
  );

describe('config tier precedence', () => {
  it('should resolve base defaults when no overlay or env applies', async () => {
    // Act
    const config = await load('base');

    // Assert
    should(config.get('app').servicetree.landscape).equal('base');
    should(config.get('branding').appName).equal('Diene Sample');
  });

  it.each([
    { landscape: 'pichu', expected: 'https://webapp.nextjs-frontend.diene.pichu.cluster.atomi.cloud' },
    { landscape: 'pikachu', expected: 'https://webapp.nextjs-frontend.diene.pikachu.cluster.atomi.cloud' },
    { landscape: 'raichu', expected: 'https://webapp.nextjs-frontend.diene.raichu.cluster.atomi.cloud' },
  ])('should let the $landscape overlay win over the base file', async ({ landscape, expected }) => {
    // Act
    const config = await load(landscape);

    // Assert — the overlay replaces the base value and leaves untouched keys alone.
    should(config.get('seo').baseUrl).equal(expected);
    should(config.get('app').servicetree.landscape).equal(landscape);
    should(config.get('branding').appName).equal('Diene Sample');
  });

  it('should let the build-time tier win over both file tiers', async () => {
    // Arrange — the bundler freezes ATOMI_-prefixed values into the artifact.
    const buildTimeEnv = { ATOMI_BRANDING__SHORT_NAME: 'FromBuild' };

    // Act
    const config = await load('pichu', { buildTimeEnv });

    // Assert
    should(config.get('branding').shortName).equal('FromBuild');
    should(config.get('seo').baseUrl).equal('https://webapp.nextjs-frontend.diene.pichu.cluster.atomi.cloud');
  });

  it('should let the runtime tier win over the build-time tier', async () => {
    // Arrange — the same key set in both tiers; runtime is applied last so a
    // deployed container can override what the build baked in.
    const buildTimeEnv = { ATOMI_BRANDING__SHORT_NAME: 'FromBuild' };
    const env = { ATOMI_BRANDING__SHORT_NAME: 'FromRuntime' };

    // Act
    const config = await load('pichu', { buildTimeEnv, env });

    // Assert
    should(config.get('branding').shortName).equal('FromRuntime');
  });

  it('should coerce and nest env keys down the block path', async () => {
    // Arrange — `__` splits the path; scalars coerce to the schema's type.
    const env = { ATOMI_FARO__ENABLED: 'true', ATOMI_PICKER__PING_TIMEOUT_MS: '4500' };

    // Act
    const config = await load('base', { env });

    // Assert
    should(config.get('faro').enabled).equal(true);
    should(config.get('picker').pingTimeoutMs).equal(4500);
  });

  it('should reject a tree that violates a block schema', async () => {
    // Arrange — validation runs over the MERGED tree, so a defect introduced by
    // the highest-precedence tier is caught exactly like one in the YAML.
    const env = { ATOMI_SEO__BASE_URL: 'not-a-url' };

    // Act
    const outcome = await load('base', { env }).then(
      () => 'loaded',
      (error: Error) => error.constructor.name,
    );

    // Assert — a validation failure, never a half-built config object.
    should(outcome).not.equal('loaded');
  });
});
