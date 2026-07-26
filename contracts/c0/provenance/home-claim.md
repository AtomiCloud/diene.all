### §13 Home claim + pre-onboarding

- **`home_landscape` is a claim checked on EVERY sign-in/sign-up**, not just
  first login:
  - **present** → route directly to the home landscape; no Doc B fetch, no
    picker.
  - **absent** (new user, or pre-onboarding user who hasn't finished the
    flow) → Doc B, the landscape selector (§10) → ping each listed region
    → pick a home → OIDC login → absent backend claim → race-safe `GET
    /User/Me`/create → onboarding phase machine (§8) → **OnboardSync writes the
    home claim** via the
    platform's own lithium Management API.
- **Claim delivery**: the claim rides the ID/access token as a custom JWT
  claim, sourced from the user's `custom_data.home_landscape` in Logto and
  emitted by a **jwt-customizer script that logto-operator owns
  declaratively** (per platform instance) — never sourced from any edge
  doc (§10) or any other runtime lookup.
- Multi-backend client machinery treats each region as just another
  registered backend (§8); the home claim only decides which backend is
  "home" for routing purposes, it doesn't change the per-backend
  onboarding contract.
