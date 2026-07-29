import { type AirwallexConfiguration, airwallexVerifier } from './airwallex.ts';
import { type AppleAppStoreConfiguration, appleAppStoreVerifier } from './apple-app-store.ts';
import { type DiscordConfiguration, discordVerifier } from './discord.ts';
import { type GooglePlayConfiguration, googlePlayVerifier } from './google-play.ts';
import { type LogtoConfiguration, logtoVerifier } from './logto.ts';
import { type StripeConfiguration, stripeVerifier } from './stripe.ts';
import { type TelegramConfiguration, telegramVerifier } from './telegram.ts';
import { type ProviderName, type ProviderVerifier, providerNames } from './types.ts';

export interface ProviderConfigurations {
  readonly stripe: StripeConfiguration;
  readonly airwallex: AirwallexConfiguration;
  readonly 'apple-app-store': AppleAppStoreConfiguration;
  readonly 'google-play': GooglePlayConfiguration;
  readonly telegram: TelegramConfiguration;
  readonly discord: DiscordConfiguration;
  readonly logto: LogtoConfiguration;
}

export type ProviderRegistry = {
  readonly [Provider in ProviderName]: ProviderVerifier<ProviderConfigurations[Provider]>;
};

export const providerRegistry: ProviderRegistry = {
  stripe: stripeVerifier,
  airwallex: airwallexVerifier,
  'apple-app-store': appleAppStoreVerifier,
  'google-play': googlePlayVerifier,
  telegram: telegramVerifier,
  discord: discordVerifier,
  logto: logtoVerifier,
};

export const isProviderName = (value: string): value is ProviderName =>
  (providerNames as readonly string[]).includes(value);

export const getProviderVerifier = <Provider extends ProviderName>(provider: Provider): ProviderRegistry[Provider] =>
  providerRegistry[provider];
