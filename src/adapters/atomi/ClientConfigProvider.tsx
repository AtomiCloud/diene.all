'use client';

import { createContext, useContext, type ReactNode } from 'react';
import type { ClientSafeConfig } from '@/config';

const ClientConfigContext = createContext<ClientSafeConfig | undefined>(undefined);

/**
 * SSR landscape payload receiver (server tells client). The server resolves
 * landscape from its runtime binding and injects the client-safe config subset
 * through this provider in the root layout; no client code ever detects the
 * landscape itself.
 */
export function ClientConfigProvider({
  config,
  children,
}: {
  readonly config: ClientSafeConfig;
  readonly children: ReactNode;
}) {
  return <ClientConfigContext.Provider value={config}>{children}</ClientConfigContext.Provider>;
}

export function useClientConfig(): ClientSafeConfig {
  const config = useContext(ClientConfigContext);
  if (config === undefined) {
    throw new Error('useClientConfig must be used inside ClientConfigProvider');
  }
  return config;
}

/** The SSR-injected landscape — the ONLY way client code learns it. */
export function useLandscape(): string {
  return useClientConfig().landscape;
}
