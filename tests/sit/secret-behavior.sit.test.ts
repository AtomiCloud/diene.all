import { cp, mkdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { describe, it } from 'bun:test';
import should from 'should';
import { consumerDriver, initialize } from './driver';

describe('blank secret behavior SIT', () => {
  it('should treat a blank runtime secret as unset and retain the file-layer secret', async () => {
    // Arrange
    const driver = consumerDriver();
    should((await initialize(driver)).code).equal(0);
    const directory = `dist/sit-config-${crypto.randomUUID()}`;
    const absolute = resolve(import.meta.dir, '../..', directory);
    await mkdir(absolute, { recursive: true });
    const settings = Bun.YAML.parse(await Bun.file('config/settings.yaml').text()) as Record<string, unknown>;
    (settings.encryption as { key: string }).key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
    await Bun.write(resolve(absolute, 'settings.yaml'), Bun.YAML.stringify(settings));
    await cp('config/lapras.settings.yaml', resolve(absolute, 'lapras.settings.yaml'));

    // Act
    const actual = await driver.run(['worker', '--once'], {
      ATOMI_ENCRYPTION__KEY: '',
      BUN_CONSUMER_CONFIG_DIR: directory,
      ATOMI_HEALTH__HEARTBEAT_FILE: `dist/run/secret-${crypto.randomUUID()}.json`,
    });

    // Assert
    should(actual.code).equal(0);
  });
});
