// Package deferred implements the deferred deep-link login primitives: the
// server-side mint/redeem module and the store-carrier builders the web client
// hands to an app store.
//
// The flow it enables is "sign in on the web, install the app, be already signed
// in". A web session mints a one-time opaque nonce, the nonce travels to the
// freshly installed app through a store carrier (the Android Install Referrer or
// the iOS clipboard), and the app redeems it for a provider one-time login token.
//
// Two lifetimes appear here and they are NOT the same thing: the nonce lives
// [authengine.DeferredTokenLifetime] (15 minutes, long enough to install an app)
// and the provider one-time token it redeems into lives
// [authengine.OneTimeTokenLifetime] (120 seconds, long enough to complete one
// login). Neither is an access-token lifetime.
//
// Handoff completes the LOGIN only. The standard per-backend onboarding gate (see
// the onboard package) still runs afterwards; there is no handoff-specific
// onboarding path.
package deferred
