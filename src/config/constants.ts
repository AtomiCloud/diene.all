export const Postgres = { Main: 'MAIN' } as const;
export const Cache = { Main: 'MAIN' } as const;
export const Kv = { Main: 'MAIN' } as const;
export const Storage = { Archive: 'ARCHIVE', Main: 'MAIN' } as const;

export const KeyedAdapterConstants = {
  cache: Object.values(Cache),
  kv: Object.values(Kv),
  postgres: Object.values(Postgres),
  storage: Object.values(Storage),
} as const;
