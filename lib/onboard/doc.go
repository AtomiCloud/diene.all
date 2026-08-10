// Package onboard implements OnboardSync: the claims-first, per-backend
// onboarding gate and the pre-onboarding home-landscape selector.
//
// Onboarding is registration plus claim write-back. A client proves token
// ownership, the backend creates its local user row for the token subject, and the
// backend writes a per-backend claim back to the identity provider so future
// tokens carry proof of registration. The claim IS the detection signal: a client
// inspects it rather than probing the backend, which is why a cold start costs
// zero API calls per backend.
//
// State is keyed PER BACKEND. There is no singleton "onboarded" flag and being
// onboarded on backend A implies nothing about backend B — "ready on A while still
// onboarding B" is a normal state a consumer's UI must be able to render. Under
// multi-region this is exactly the machinery federation rides: a region is just
// another backend.
//
// Two claims appear and they are independent: the per-backend registration claim
// (`<platform>_<service>`) gates onboarding, while the home-landscape claim decides
// which region's backends a client talks to at all. The selector below resolves the
// second BEFORE any backend phase machine runs.
package onboard
