#!/usr/bin/env bash
set -euo pipefail

# Registers everything Apple-side that CI's API key cannot — run by an App
# Manager/Admin, locally, with their own Apple ID. Idempotent: re-run any time
# a new signing target (widget, watch app, …) or landscape is added.
#
# Flow: one interactive sign-in up front (password + a single 2FA prompt on
# this terminal — fastlane caches the session locally), then every landscape
# is processed automatically and non-interactively.
#
# Per landscape it ensures:
#   1. the App Group          group.<app bundle id>
#   2. every App ID           (app + extensions, discovered from the Xcode project)
#   3. the App Groups capability on each App ID
#   4. the group ⇄ App ID association
#   5. the App Store Connect  app record (the store bucket TestFlight uploads
#      into) — and writes its numeric apple_id into lpsm.yaml
#
# The ONE Apple-side thing it can't do: free up an app NAME still held by a
# pre-migration app record. If a name is taken, that landscape is reported at
# the end — rename the old app in App Store Connect and re-run.
# Google Play app creation has no API at all; those stay manual (see
# docs/developer/flutter-baseline.md).
#
# CI/CD never needs this: it stays API-key-only (fetch-signing-files --create
# self-heals certs/profiles) and scripts/ci/doctor-ios.sh verifies the group is
# wired by decoding the fetched profiles.
#
# Env:
#   FASTLANE_USER          Apple ID email (skips the prompt). Must be an Apple ID
#                          on the team in lpsm.yaml — accounts outside the team
#                          fail with "account is in no teams".
#   FASTLANE_TEAM_ID       Developer-portal team (skips the team menu)
#   FASTLANE_ITC_TEAM_ID   App Store Connect team (skips the team menu)
#   FLUTTER_BASE_APP_NAME          Override the App Store base name from lpsm.yaml
#
# Usage: ./scripts/local/register-apple.sh [landscape ...]   (default: all in lpsm.yaml)

export FASTLANE_SKIP_UPDATE_CHECK=1
export FASTLANE_OPT_OUT_USAGE=1
export FASTLANE_HIDE_CHANGELOG=1

HERE="$(cd "$(dirname "$0")" && pwd)"
LPSM="$HERE/../../lpsm.yaml"

for tool in fastlane yq; do
  if ! command -v "$tool" >/dev/null; then
    echo "✗ $tool not found — run this inside the dev shell (direnv / nix develop)." >&2
    exit 1
  fi
done

# Everything identity-shaped comes from lpsm.yaml — the single source of truth.
PROJECT_TEAM_ID=$(yq '.apple_team' "$LPSM")
APP_NAME=${FLUTTER_BASE_APP_NAME:-$(yq '.app_name' "$LPSM")}
DOMAIN=$(yq '.domain' "$LPSM")
PLATFORM=$(yq '.platform' "$LPSM")
SERVICE=$(yq '.service' "$LPSM")

LANDSCAPES=("$@")
if [ ${#LANDSCAPES[@]} -eq 0 ]; then
  while IFS= read -r l; do LANDSCAPES+=("$l"); done < <(yq '.landscapes[].name' "$LPSM")
fi

# The public-facing App Store name: base name + the landscape's store_suffix
# from lpsm.yaml (prod bare, others suffixed — store names are globally
# unique). Names remain editable in App Store Connect until first release.
store_name() {
  local suffix
  suffix=$(yq ".landscapes[] | select(.name == \"$1\") | .store_suffix // \"\"" "$LPSM")
  echo "$APP_NAME$suffix"
}

# ── 1. Sign in once, interactively ──────────────────────────────────────────
# Everything after this runs with output captured (for error triage), which
# breaks interactive prompts — so all interaction happens here, on the TTY.
APPLE_ID=${FASTLANE_USER:-}
if [ -z "$APPLE_ID" ]; then
  read -r -p "Apple ID email (needs App Manager/Admin role): " APPLE_ID </dev/tty
fi
export FASTLANE_USER="$APPLE_ID"

echo
echo "==> Signing in to the Apple Developer portal as $APPLE_ID"
echo "    Expect a password prompt and one 2FA code. fastlane will then print a"
echo "    long FASTLANE_SESSION blob — ignore it; the session is cached locally."
echo
fastlane spaceauth -u "$APPLE_ID"

# Throwaway Fastfile: team enumeration + apple_id lookup lanes, run with
# fastlane's own ruby/gems so Spaceship is available.
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/fastlane"
cat >"$tmpdir/fastlane/Fastfile" <<'RUBY'
lane :teams do
  require "spaceship"
  Spaceship::Portal.login(ENV["FASTLANE_USER"])
  Spaceship::Portal.client.teams.each do |t|
    puts "TEAM\t#{t["teamId"]}\t#{t["name"]}"
  end
  Spaceship::Tunes.login(ENV["FASTLANE_USER"])
  Spaceship::Tunes.client.teams.each do |t|
    puts "ITCTEAM\t#{t["contentProvider"]["contentProviderId"]}\t#{t["contentProvider"]["name"]}"
  end
end

lane :rotate_profiles do
  require "spaceship"
  # Profiles minted before a group association never gain it retroactively,
  # and CD reuses any valid existing profile — delete ours so the next CD run
  # mints fresh ones carrying the current entitlements. Must go through
  # ConnectAPI: Apple retired the legacy portal provisioning endpoints (they
  # now answer "Please update to Xcode 7.3").
  Spaceship::ConnectAPI.login(
    ENV["FASTLANE_USER"],
    use_portal: true,
    use_tunes: false,
    portal_team_id: ENV["FASTLANE_TEAM_ID"]
  )
  ids = ENV["FLUTTER_BASE_BUNDLE_IDS"].split(",")
  Spaceship::ConnectAPI::Profile.all(includes: "bundleId").each do |p|
    bid = p.bundle_id && p.bundle_id.identifier
    next unless ids.include?(bid)
    puts "ROTATE\t#{bid}\t#{p.name}"
    p.delete!
  end
end

lane :appids do
  require "spaceship"
  # ConnectAPI (web-session), not the legacy Spaceship::Tunes — Apple has been
  # dismantling the old iTC endpoints and Tunes lookups fail on modern fastlane.
  # An ASC app's resource id IS the numeric Apple ID.
  Spaceship::ConnectAPI.login(
    ENV["FASTLANE_USER"],
    use_portal: false,
    use_tunes: true,
    tunes_team_id: ENV["FASTLANE_ITC_TEAM_ID"]
  )
  ENV["FLUTTER_BASE_BUNDLE_IDS"].split(",").each do |bid|
    app = Spaceship::ConnectAPI::App.find(bid)
    puts "APP\t#{bid}\t#{app ? app.id : ""}"
  end
end
RUBY

# ── 2. Pick the teams ─────────────────────────────────────────────────────────
# An Apple ID can belong to several teams — on BOTH sides: the Developer portal
# (signing) and App Store Connect (store records) have separate team ids.
# fastlane's own chooser would fire mid-loop where output is captured (an
# invisible hang), so enumerate and choose everything up front.
echo
echo "==> Looking up your teams…"
# fastlane timestamps every captured line ("[23:16:29]: TEAM…"), so match the
# marker anywhere and strip everything before it.
team_lines=$( (cd "$tmpdir" && fastlane teams 2>&1) | sed -nE 's/.*\b(ITCTEAM|TEAM)\t/\1\t/p' || true)

# pick_team <label> <lines> <default_id> — prints the chosen id.
pick_team() {
  local label=$1 lines=$2 default_id=$3
  local n
  n=$(wc -l <<<"$lines")
  if [ "$n" -eq 1 ]; then
    echo "  ✓ $label team: $(cut -f3 <<<"$lines") ($(cut -f2 <<<"$lines"))" >&2
    cut -f2 <<<"$lines"
    return
  fi
  echo "Your Apple ID belongs to multiple $label teams:" >&2
  local i=0 default_idx=1 tid tname
  while IFS=$'\t' read -r _ tid tname; do
    i=$((i + 1))
    local marker=""
    if [ "$tid" = "$default_id" ]; then
      marker="   ← this project's team"
      default_idx=$i
    fi
    echo "  $i) $tname ($tid)$marker" >&2
  done <<<"$lines"
  local sel
  read -r -p "Select $label team [$default_idx]: " sel </dev/tty
  sel=${sel:-$default_idx}
  local chosen
  chosen=$(sed -n "${sel}p" <<<"$lines" | cut -f2)
  if [ -z "$chosen" ]; then
    echo "✗ invalid selection: $sel" >&2
    exit 1
  fi
  echo "$chosen"
}

portal_teams=$(grep $'^TEAM\t' <<<"$team_lines" || true)
itc_teams=$(grep $'^ITCTEAM\t' <<<"$team_lines" || true)

if [ -z "${FASTLANE_TEAM_ID:-}" ]; then
  if [ -z "$portal_teams" ]; then
    echo "  (could not enumerate portal teams — using the project team $PROJECT_TEAM_ID)"
    FASTLANE_TEAM_ID=$PROJECT_TEAM_ID
  elif ! grep -q $'^TEAM\t'"$PROJECT_TEAM_ID"$'\t' <<<"$portal_teams" &&
    [ -z "${FLUTTER_BASE_ALLOW_FOREIGN_TEAM:-}" ]; then
    # Registering App IDs/Groups into the wrong team (e.g. a personal one) makes
    # them invisible to CI, whose API key belongs to the project team — refuse.
    echo "✗ Your Apple ID has NO Developer-portal access to the project team ($PROJECT_TEAM_ID)." >&2
    echo >&2
    echo "  Portal teams your Apple ID can see:" >&2
    cut -f2,3 <<<"$portal_teams" | sed 's/^/    - /' >&2
    echo >&2
    echo "  App Store Connect and the Developer portal have SEPARATE access: you can" >&2
    echo "  be on the ASC team yet lack the signing side. An org Admin must grant your" >&2
    echo "  user 'Access to Certificates, Identifiers & Profiles' (App Store Connect →" >&2
    echo "  Users and Access → your user → Developer Resources), or an Admin runs this." >&2
    echo >&2
    echo "  To intentionally register under a different team anyway:" >&2
    echo "    FLUTTER_BASE_ALLOW_FOREIGN_TEAM=1 pls mobile:register-apple" >&2
    exit 1
  else
    FASTLANE_TEAM_ID=$(pick_team "Developer-portal" "$portal_teams" "$PROJECT_TEAM_ID")
  fi
fi
export FASTLANE_TEAM_ID

if [ -z "${FASTLANE_ITC_TEAM_ID:-}" ]; then
  if [ -n "$itc_teams" ]; then
    FASTLANE_ITC_TEAM_ID=$(pick_team "App Store Connect" "$itc_teams" "")
    export FASTLANE_ITC_TEAM_ID
  else
    # Without a team hint fastlane would prompt interactively on multi-team
    # accounts — inside captured output that's an invisible hang, so say so.
    echo "  ⚠ could not enumerate App Store Connect teams — continuing without a"
    echo "    team hint (fine for single-team accounts). If a later step hangs,"
    echo "    abort and re-run with FASTLANE_ITC_TEAM_ID=<numeric ASC team id>."
  fi
fi
echo "==> Registering under portal team $FASTLANE_TEAM_ID${FASTLANE_ITC_TEAM_ID:+, ASC team $FASTLANE_ITC_TEAM_ID}"

# ── helpers ──────────────────────────────────────────────────────────────────
# All run a fastlane command silently and print a one-line result; on a real
# failure they dump fastlane's full output. `ensure` additionally tolerates the
# benign "resource already exists" failure (the idempotent re-run case).
run() {
  local label=$1
  shift
  local out
  if out=$("$@" 2>&1); then
    echo "  ✓ $label"
    return 0
  fi
  echo "  ✗ $label" >&2
  printf '%s\n' "$out" >&2
  return 1
}

ensure() {
  local label=$1
  shift
  local out
  if out=$("$@" 2>&1); then
    echo "  ✓ $label (created)"
    return 0
  fi
  if grep -qiE "already exist|already been taken" <<<"$out"; then
    echo "  ✓ $label (already exists)"
    return 0
  fi
  # "not available" = the globally-unique identifier is claimed or reserved
  # OUTSIDE this team — either registered in another team (delete it there) or
  # recently deleted (Apple reserves deleted identifiers for up to ~48h; if it
  # never frees, Apple Developer Support can release it).
  if grep -qi "is not available" <<<"$out"; then
    echo "  ✗ $label — identifier taken or reserved outside this team" >&2
    echo "    → if it exists in another team (e.g. a personal one), delete it there;" >&2
    echo "      if you just deleted it, Apple holds it for up to ~48h — re-run later" >&2
    echo "      (this script is idempotent). Still stuck? Apple Developer Support" >&2
    echo "      can release the identifier." >&2
    return 1
  fi
  echo "  ✗ $label" >&2
  printf '%s\n' "$out" >&2
  return 1
}

# Like `ensure`, but for the ASC app record: a name conflict (the old app still
# holds the store name) is reported and skipped instead of failing the run.
# Returns 0 ok/exists, 2 name conflict, 1 real error.
ensure_record() {
  local label=$1
  shift
  local out
  if out=$("$@" 2>&1); then
    echo "  ✓ $label"
    return 0
  fi
  if grep -qiE "already being used|is not available" <<<"$out"; then
    echo "  ⚠ $label — the store NAME is taken (rename the old app, then re-run)"
    return 2
  fi
  if grep -qiE "already exist" <<<"$out"; then
    echo "  ✓ $label (already exists)"
    return 0
  fi
  echo "  ✗ $label" >&2
  printf '%s\n' "$out" >&2
  return 1
}

# ── 3. Register every landscape ──────────────────────────────────────────────
PENDING_RENAME=()
APP_IDS=()
ALL_TARGET_IDS=()
for L in "${LANDSCAPES[@]}"; do
  # Captured (not process-substituted) so a discovery failure aborts the run.
  targets=$("$HERE/../ci/ios-signing-targets.sh" "$L")
  # The App Group is `group.` + the app's bundle id — the first (shortest) target.
  app_bundle_id="${targets%%$'\n'*}"
  GROUP="group.$app_bundle_id"
  APP_IDS+=("$app_bundle_id")

  echo
  echo "==> $L"
  ensure "App Group $GROUP" \
    fastlane produce group -g "$GROUP" -n "$APP_NAME $L shared"

  while IFS= read -r bundle_id; do
    ALL_TARGET_IDS+=("$bundle_id")
    module=${bundle_id#"$DOMAIN"."$L"."$PLATFORM"."$SERVICE".}
    name="$APP_NAME $L ${module//./ }"

    ensure "App ID $bundle_id" \
      fastlane produce -a "$bundle_id" --app_name "$name" --skip_itc

    # Capabilities are IaC: lpsm.yaml's `capabilities.<module>` declares the
    # full set as fastlane `produce enable_services` flag names, applied
    # verbatim. Enable-only — removing a declaration does not disable the
    # capability in the portal. Profiles embed the capability list, so any
    # change here relies on the rotation step below to reach signatures.
    caps=$(yq ".capabilities.\"$module\" // [] | .[]" "$LPSM")
    if [ -z "$caps" ]; then
      echo "  ✗ no capabilities declared for module '$module' in lpsm.yaml" >&2
      exit 1
    fi
    while IFS= read -r cap; do
      run "  capability --$cap on $bundle_id" \
        fastlane produce enable_services "--$cap" -a "$bundle_id"
    done <<<"$caps"

    run "  associate $GROUP" \
      fastlane produce associate_group -a "$bundle_id" "$GROUP"
  done <<<"$targets"

  # The store app record (main app only — extensions ship inside the app).
  rc=0
  ensure_record "ASC app record '$(store_name "$L")' ($app_bundle_id)" \
    fastlane produce -a "$app_bundle_id" \
    --app_name "$(store_name "$L")" \
    --sku "$app_bundle_id" \
    --language en-US || rc=$?
  if [ "$rc" -eq 2 ]; then
    PENDING_RENAME+=("$L")
  elif [ "$rc" -ne 0 ]; then
    exit "$rc"
  fi
done

# ── 4. Rotate provisioning profiles ──────────────────────────────────────────
# A profile minted before a group association never gains it retroactively, and
# CD reuses any valid existing profile — the doctor would then fail forever
# ("profile lacks App Group"). Delete our targets' App Store profiles; the next
# CD run mints fresh ones carrying the current entitlements.
echo
echo "==> Rotating provisioning profiles (CD re-mints them with current entitlements)"
rotate_out=$(
  cd "$tmpdir" &&
    FLUTTER_BASE_BUNDLE_IDS=$(
      IFS=,
      echo "${ALL_TARGET_IDS[*]}"
    ) fastlane rotate_profiles 2>&1
) || true
rotated=$(sed -nE 's/.*ROTATE\t/  ✓ deleted profile for /p' <<<"$rotate_out" | tr '\t' ' ' || true)
if [ -n "$rotated" ]; then
  printf '%s\n' "$rotated"
elif grep -qi "error" <<<"$rotate_out"; then
  echo "  ⚠ profile rotation failed — if the CD doctor reports a profile lacking" >&2
  echo "    the App Group, delete the stale profiles at developer.apple.com →" >&2
  echo "    Profiles and re-run CD. fastlane said:" >&2
  tail -4 <<<"$rotate_out" | sed 's/^/    /' >&2
else
  echo "  (no existing profiles to rotate)"
fi

# ── 5. Fill apple_ids into lpsm.yaml ──────────────────────────────────────────
# The numeric ASC app id feeds get-latest-build-number in CD; look each one up
# and write it into lpsm.yaml (the source of truth the CD matrix reads).
echo
echo "==> Looking up numeric apple_ids…"
appids_out=$(
  cd "$tmpdir" &&
    FLUTTER_BASE_BUNDLE_IDS=$(
      IFS=,
      echo "${APP_IDS[*]}"
    ) fastlane appids 2>&1
) || true
# Strip fastlane's timestamp prefix before parsing ("[23:16:29]: APP…").
ids=$(sed -nE 's/.*\bAPP\t/APP\t/p' <<<"$appids_out" || true)
patched=0
while IFS=$'\t' read -r _ bid aid; do
  [ -n "$bid" ] || continue
  land=""
  while IFS= read -r candidate; do
    [[ $bid == "$DOMAIN.$candidate.$PLATFORM.$SERVICE."* ]] && land=$candidate && break
  done < <(yq '.landscapes[].name' "$LPSM")
  [ -z "$land" ] && echo "  ✗ could not map $bid back to an lpsm landscape" >&2 && continue
  if [ -z "$aid" ]; then
    echo "  ⚠ $land: no ASC app record found for $bid — apple_id not filled" >&2
    continue
  fi
  current=$(yq ".landscapes[] | select(.name == \"$land\") | .apple_id" "$LPSM")
  if [ "$current" = "$aid" ]; then
    echo "  ✓ $land: apple_id $aid (already in lpsm.yaml)"
    continue
  fi
  yq -i "(.landscapes[] | select(.name == \"$land\") | .apple_id) = \"$aid\"" "$LPSM"
  echo "  ✓ $land: apple_id $aid → written to lpsm.yaml"
  patched=1
done <<<"$ids"
if [ -z "$ids" ]; then
  # Don't pretend the records don't exist when the lookup itself broke.
  echo "  ⚠ apple_id lookup returned nothing — fastlane's last lines:" >&2
  tail -6 <<<"$appids_out" | sed 's/^/    /' >&2
  echo "    Records can lag a few minutes after creation; re-run later, or fill" >&2
  echo "    the apple_id fields in lpsm.yaml by hand (ASC → App Information)." >&2
fi

# ── 6. Summary ────────────────────────────────────────────────────────────────
echo
echo "✅ Registered ${#LANDSCAPES[@]} Apple landscape(s): ${LANDSCAPES[*]}"
echo "CI verifies the signing wiring on every release (scripts/ci/doctor-ios.sh)."
if [ ${#PENDING_RENAME[@]} -gt 0 ]; then
  echo
  echo "⚠ Store names still held by the old apps for: ${PENDING_RENAME[*]}"
  echo "  → In App Store Connect, rename the old app(s) (e.g. suffix ' OLD'),"
  echo "    then re-run: pls mobile:register-apple"
fi
if [ "$patched" -eq 1 ]; then
  echo
  echo "lpsm.yaml was updated with apple_id(s) — review and commit it:"
  echo "  git diff lpsm.yaml"
fi
echo
echo "Still manual (no API exists) — see docs/developer/flutter-baseline.md:"
echo "  • Google Play Console apps"
echo "  • Logto redirect URIs"
echo
echo "If a step hangs, the cached Apple session likely expired — re-run this script."
