const string = (pattern?: string) => ({
  type: 'string',
  ...(pattern == null ? {} : { pattern }),
});

const object = (required: string[], properties: Record<string, unknown>) => ({
  type: 'object',
  required,
  properties,
  additionalProperties: false,
});

const schema = {
  $schema: 'https://json-schema.org/draft/2020-12/schema',
  $id: 'https://schemas.example.invalid/diene-flutter-base/config.schema.json',
  title: 'Diene Flutter Base Configuration',
  type: 'object',
  required: ['app', 'branding', 'theme', 'locale', 'auth', 'session', 'api', 'notifications', 'onboarding'],
  properties: {
    $schema: string(),
    app: object(['landscape', 'platform', 'service', 'module', 'version'], {
      landscape: string('^(lapras|pichu|pikachu|raichu)$'),
      platform: string('^[a-z][a-z0-9-]*$'),
      service: string('^[a-z][a-z0-9-]*$'),
      module: string('^[a-z][a-z0-9-]*$'),
      version: string('^[0-9]+\\.[0-9]+\\.[0-9]+$'),
    }),
    branding: object(['appName', 'shortName', 'logoAsset', 'iconAsset'], {
      appName: string('.+'),
      shortName: string('.+'),
      logoAsset: string('^assets/'),
      iconAsset: string('^assets/'),
    }),
    theme: object(['mode', 'primary', 'secondary', 'surfaceTint', 'radius'], {
      mode: { enum: ['light', 'dark', 'system'] },
      primary: string('^#[0-9A-Fa-f]{6}$'),
      secondary: string('^#[0-9A-Fa-f]{6}$'),
      surfaceTint: string('^#[0-9A-Fa-f]{6}$'),
      radius: { type: 'number', minimum: 0 },
    }),
    locale: object(['defaultLocale', 'supportedLocales'], {
      defaultLocale: string('^[a-z]{2}(-[A-Z]{2})?$'),
      supportedLocales: {
        type: 'array',
        minItems: 2,
        uniqueItems: true,
        items: string('^[a-z]{2}(-[A-Z]{2})?$'),
      },
    }),
    auth: object(['demoMode', 'endpoint', 'clientId', 'resource', 'redirectUri', 'scopes'], {
      demoMode: { type: 'boolean' },
      endpoint: string('^https?://'),
      clientId: string('.+'),
      resource: string('^https?://'),
      redirectUri: string('^[a-z][a-z0-9.-]+://callback$'),
      scopes: {
        type: 'array',
        minItems: 1,
        uniqueItems: true,
        items: string('.+'),
      },
    }),
    session: object(['accessMinutes', 'refreshDays'], {
      accessMinutes: { const: 10 },
      refreshDays: { const: 14 },
    }),
    api: object(['baseUrl'], { baseUrl: string('^https?://') }),
    notifications: object(['enabled', 'topic'], { enabled: { type: 'boolean' }, topic: string('.+') }),
    onboarding: object(['backendId'], { backendId: string('.+') }),
  },
  additionalProperties: false,
};

console.log(`${JSON.stringify(schema, null, 2)}\n`);
