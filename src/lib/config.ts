import { z } from 'zod';

const nonBlankStringSchema = z.string().trim().min(1);
const nonBlankSecretSchema = z.string().refine(value => value.trim() !== '', {
  message: 'Secret must not be blank.',
});
const httpEndpointSchema = z
  .url()
  .refine(value => value.startsWith('https://') || value.startsWith('http://'), {
    message: 'Endpoint must use http or https.',
  })
  .superRefine((value, context) => {
    if (!URL.canParse(value)) return;
    const url = new URL(value);
    if (url.username !== '' || url.password !== '' || url.pathname !== '/' || url.search !== '' || url.hash !== '') {
      context.addIssue({
        code: 'custom',
        message: 'Endpoint must be a canonical origin without credentials, path, query, or fragment.',
      });
    }
  });
const mountPathSchema = z
  .string()
  .regex(/^\/(?!\/)(?!.*\/\/)(?!.*[\\%?#\s]).*$/, {
    message:
      'Mount must be an absolute, unencoded path without an authority, empty segment, whitespace, query, fragment, or backslash.',
  })
  .refine(value => !/(^|\/)\.{1,2}(\/|$)/.test(value), {
    message: 'Mount must not contain dot-path traversal segments.',
  });

export const authEngineConfigSchema = z
  .object({
    logto: z
      .object({
        endpoint: httpEndpointSchema,
        appId: nonBlankStringSchema,
        appSecret: nonBlankSecretSchema,
        management: z
          .object({
            endpoint: httpEndpointSchema,
            clientId: nonBlankStringSchema,
            clientSecret: nonBlankSecretSchema,
          })
          .strict(),
      })
      .strict(),
    handoff: z
      .object({
        mount: mountPathSchema.default('/app-handoff'),
      })
      .strict(),
    store: z
      .object({
        kind: z.literal('redis'),
        host: nonBlankStringSchema,
        port: z.number().int().min(1).max(65_535),
      })
      .strict(),
  })
  .strict();

export type AuthEngineConfig = z.infer<typeof authEngineConfigSchema>;
