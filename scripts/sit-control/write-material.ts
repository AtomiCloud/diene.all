import { randomBytes } from 'node:crypto';
import { mkdir, readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { getPublicKeyAsync, utils } from '@noble/ed25519';
import { exportJWK, exportPKCS8, exportSPKI, generateKeyPair } from 'jose';

const target = process.argv[2];
if (target === undefined || !target.startsWith('/')) {
  throw new Error('write-material requires an absolute target directory');
}
const publicOrigin = process.env.MERCURY_SIT_PUBLIC_ORIGIN?.trim() || 'https://127.0.0.1:8443';

const text = (bytes = 48): string => randomBytes(bytes).toString('base64url');
const write = (path: string, value: string): Promise<number> =>
  Bun.write(resolve(target, path), value.endsWith('\n') ? value : `${value}\n`);
const json = (path: string, value: unknown): Promise<number> => write(path, JSON.stringify(value));

await mkdir(resolve(target, 'providers'), { recursive: true });
await mkdir(resolve(target, 'endpoints'), { recursive: true });

const consoleKeys = await generateKeyPair('ES256', { extractable: true });
await write('console-authorization-private-key', await exportPKCS8(consoleKeys.privateKey));
await write('console-authorization-public-key', await exportSPKI(consoleKeys.publicKey));

const googleKeys = await generateKeyPair('RS256', { extractable: true });
const googlePrivateKey = await exportPKCS8(googleKeys.privateKey);
await write('google-private-key.pem', googlePrivateKey);
await json('providers/google-play.json', {
  key: await exportJWK(googleKeys.publicKey),
  serviceAccountEmail: 'mercury-sit@mercury-sit.iam.gserviceaccount.com',
  audience: `${publicOrigin}/t/sit/google-play`,
});
await json('providers/google-pubsub-service-account.json', {
  type: 'service_account',
  private_key_id: 'mercury-sit-google',
  private_key: googlePrivateKey,
  client_email: 'mercury-sit@mercury-sit.iam.gserviceaccount.com',
  token_uri: 'https://oauth2.googleapis.com/token',
});

const discordSecret = utils.randomSecretKey();
const discordPublic = await getPublicKeyAsync(discordSecret);
await write('discord-secret.hex', Buffer.from(discordSecret).toString('hex'));
await json('providers/discord.json', {
  publicKeys: [Buffer.from(discordPublic).toString('hex')],
  toleranceSeconds: 300,
});

const sharedHmac = text();
await json('providers/stripe.json', { secrets: [sharedHmac], toleranceSeconds: 300 });
await json('providers/airwallex.json', { secrets: [sharedHmac], toleranceSeconds: 300 });
await json('providers/telegram.json', { secrets: [sharedHmac] });
await json('providers/logto.json', { secrets: [sharedHmac] });
await write('provider-hmac-secret', sharedHmac);

const appleRoot = await readFile(resolve(target, 'ca/apple-root.pem'), 'utf8');
await write('providers/apple-app-store-history.p8', await readFile(resolve(target, 'ca/apple-leaf-key.pem'), 'utf8'));
await json('providers/apple-app-store.json', {
  trustedRootCertificates: [appleRoot],
  bundleId: 'cloud.atomi.mercury.sit',
  environment: 'Sandbox',
  appAppleId: 123456789,
});

const endpointSecret = text();
for (const name of ['coordinate', 'external', 'single']) {
  await write(`endpoints/${name}`, endpointSecret);
}
await write('endpoint-signing-secret', endpointSecret);

for (const [name, value] of [
  ['console-session-secret', text()],
  ['management-bootstrap-token', text()],
  ['archive-access-key-id', 'mercury'],
  ['archive-secret-access-key', 'mercury-secret'],
  ['sit-control-bearer', text()],
  ['landscape-native-credential', text()],
] as const) {
  await write(name, value);
}
