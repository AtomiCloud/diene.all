# Mobile store Layer C runbook

Layer C is manual pre-release evidence. Never claim it from static wiring or
without real credentials and store receipts.

## Residue checklist

- Create and contract the Apple Developer and Google Play organization
  accounts; accept current agreements and tax/banking terms.
- Run `pls mobile:register-apple`, review the `lpsm.yaml` Apple IDs, and commit
  them. Create the four Play application records manually because Play exposes
  no app-creation API.
- Configure the listed GitHub secrets, Logto callback URIs, store listings,
  privacy declarations, screenshots, support URLs, and age/content ratings.
- Bootstrap each store with its first upload before relying on automated
  version-number queries.

## Pre-release proof

1. Run all local gates and four flavor builds from a clean release commit.
2. Dispatch CD for one non-production landscape.
3. Record the workflow run, stamp-doctor output, TestFlight processing result,
   and Play internal-track release.
4. Install both builds, sign in, verify the home-claim/onboarding path, switch
   locale/theme, and exercise notifications.
5. Promote within that landscape manually. Store promotion is never a Kargo
   stage and the repository never merges or promotes itself.

External review submission, TestFlight-to-App-Store promotion, and Play
internal-to-production promotion remain deliberate human actions.
