#!/usr/bin/env bash
set -euo pipefail

# Re-badges the single built AAB into one landscape's release artifact — the
# Android half of the build-once/stamp-per-landscape CD model. The Dart binary
# is landscape-agnostic by design (bundle-id-as-marker, docs/developer/standard/
# flutter-baseline.md), so the only per-landscape content is packaging: applicationId
# (== Logto scheme == provider-authority prefixes), display name, launcher-icon
# art, and versionCode. All of it lives in two protobuf files and a handful of
# PNG entries, patched here without rebuilding.
#
# Usage:
#   stamp-android.sh <in.aab> <landscape> <version-code> <out.aab>
#
# Env:
#   ANDROID_KEYSTORE_PATH      upload keystore (.jks) — re-sign after patching
#   ANDROID_KEYSTORE_PASSWORD / ANDROID_KEY_ALIAS / ANDROID_KEY_PASSWORD
#
# Needs: protoc + bundletool + jarsigner (nix cd-android shell), yq.
#
# Invariants this relies on (verified 2026-07-07, see docs/github-actions-release.md):
#   - resource namespace is constant across flavors, so resources.pb only carries
#     the applicationId in its top-level package_name field;
#   - per-flavor res dirs differ ONLY in launcher PNG bytes (same names/paths);
#   - release PNG crunching is disabled (isCrunchPngs=false), so repo PNG bytes
#     land verbatim in the AAB and can be swapped 1:1;
#   - the protoc text-format round-trip must never edit inside the source_pool
#     `data:` blob (length-prefixed string pool — any width change corrupts it).

# version-name (optional 5th arg): set when the donor was built before the
# release tag existed (CI-built donors carry pubspec's version); empty keeps
# the donor's versionName.
IN=$1 LANDSCAPE=$2 VERSION_CODE=$3 OUT=$4 VERSION_NAME=${5:-}

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROTO_DIR="$ROOT/scripts/ci/proto"
LPSM="$ROOT/lpsm.yaml"
GRADLE="$ROOT/android/app/flavorizr.gradle.kts"

DOMAIN=$(yq '.domain' "$LPSM")
P=$(yq '.platform' "$LPSM")
S=$(yq '.service' "$LPSM")
NEW_ID="$DOMAIN.$LANDSCAPE.$P.$S.app"
yq -e ".landscapes[] | select(.name == \"$LANDSCAPE\")" "$LPSM" >/dev/null || {
  echo "❌ stamp-android: unknown landscape '$LANDSCAPE'" >&2
  exit 1
}

# Display name comes from the gradle flavor block — the file that defines it —
# so the stamp can never drift from what a real per-flavor build would produce.
NEW_LABEL=$(awk -v l="$LANDSCAPE" '
  $0 ~ "create\\(\"" l "\"\\)" { in_flavor = 1 }
  in_flavor && /manifestPlaceholders\["appName"\]/ {
    sub(/.*= *"/, ""); sub(/".*/, ""); print; exit
  }' "$GRADLE")
[ -n "$NEW_LABEL" ] || {
  echo "stamp-android: no appName for flavor '$LANDSCAPE' in $GRADLE" >&2
  exit 1
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp "$IN" "$OUT"
OUT_ABS=$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")

decode() { protoc --proto_path="$PROTO_DIR" --decode="$1" "$PROTO_DIR/Resources.proto"; }
encode() { protoc --proto_path="$PROTO_DIR" --encode="$1" "$PROTO_DIR/Resources.proto"; }

# --- manifest ---------------------------------------------------------------
unzip -qq "$OUT" base/manifest/AndroidManifest.xml -d "$WORK"
decode aapt.pb.XmlNode <"$WORK/base/manifest/AndroidManifest.xml" >"$WORK/manifest.txt"

OLD_ID=$(awk '/name: "package"/ { grab = 1 } grab && /value: "/ {
  sub(/.*value: "/, ""); sub(/".*/, ""); print; exit }' "$WORK/manifest.txt")
# The application label is the first android:label in the tree (the
# <application> element precedes its activities in document order).
OLD_LABEL=$(awk '/name: "label"/ { grab = 1 } grab && /value: "/ {
  sub(/.*value: "/, ""); sub(/".*/, ""); print; exit }' "$WORK/manifest.txt")
[ -n "$OLD_ID" ] && [ -n "$OLD_LABEL" ] || {
  echo "stamp-android: failed to read package/label from manifest" >&2
  exit 1
}

# One pass: swap the applicationId everywhere it appears (package attr, Logto
# scheme, provider authorities, dynamic-receiver permissions), retag the app
# label, rewrite versionCode (its attribute carries the value twice: the raw
# string and the compiled int), and — when given — versionName (plain string
# attribute, no compiled twin).
awk -v old_id="$OLD_ID" -v new_id="$NEW_ID" \
  -v old_label="$OLD_LABEL" -v new_label="$NEW_LABEL" \
  -v vc="$VERSION_CODE" -v vn="$VERSION_NAME" '
  /name: "versionCode"/ { in_vc = 1 }
  in_vc && /value: "/            { sub(/value: "[^"]*"/, "value: \"" vc "\"") }
  in_vc && /int_decimal_value: / { sub(/int_decimal_value: [0-9]*/, "int_decimal_value: " vc); in_vc = 0 }
  /name: "versionName"/ { in_vn = 1 }
  in_vn && /value: "/ {
    if (vn != "") sub(/value: "[^"]*"/, "value: \"" vn "\"")
    in_vn = 0
  }
  /name: "label"/ { in_label = 1 }
  in_label && /value: "/ {
    if (index($0, "value: \"" old_label "\"")) sub(/value: "[^"]*"/, "value: \"" new_label "\"")
    in_label = 0
  }
  { gsub(old_id, new_id); print }
' "$WORK/manifest.txt" >"$WORK/manifest.new.txt"

encode aapt.pb.XmlNode <"$WORK/manifest.new.txt" >"$WORK/base/manifest/AndroidManifest.xml"
(cd "$WORK" && zip -qq "$OUT_ABS" base/manifest/AndroidManifest.xml)

# --- resource table ----------------------------------------------------------
# ONLY the top-level package_name field may change. Everything else in the
# table is either landscape-independent or inert source-path diagnostics whose
# string pool must not be touched (see invariants above).
unzip -qq "$OUT" base/resources.pb -d "$WORK"
decode aapt.pb.ResourceTable <"$WORK/base/resources.pb" >"$WORK/restable.txt"
sed -e "s|^\( *package_name: \)\"$OLD_ID\"|\1\"$NEW_ID\"|" \
  "$WORK/restable.txt" >"$WORK/restable.new.txt"
encode aapt.pb.ResourceTable <"$WORK/restable.new.txt" >"$WORK/base/resources.pb"
(cd "$WORK" && zip -qq "$OUT_ABS" base/resources.pb)

# --- launcher icons ----------------------------------------------------------
# Swap PNG bytes at their existing AAB paths (aapt2 appends -v4 to density
# qualifiers). XML/values resources are identical across flavors and stay put.
ENTRIES=$(unzip -Z1 "$OUT")
find "$ROOT/android/app/src/$LANDSCAPE/res" -name '*.png' | while IFS= read -r png; do
  qualifier=$(basename "$(dirname "$png")")
  name=$(basename "$png")
  entry=""
  for cand in "base/res/$qualifier-v4/$name" "base/res/$qualifier/$name"; do
    if grep -qxF "$cand" <<<"$ENTRIES"; then entry=$cand && break; fi
  done
  [ -n "$entry" ] || {
    echo "stamp-android: no AAB entry for $qualifier/$name" >&2
    exit 1
  }
  mkdir -p "$WORK/$(dirname "$entry")"
  cp "$png" "$WORK/$entry"
  (cd "$WORK" && zip -qq "$OUT_ABS" "$entry")
done

# --- baked configuration -----------------------------------------------------
# The donor compiles the raichu selector once. Stamping replaces that selected
# asset with the target overlay, so the release still has one baked landscape
# and performs no hostname/package/runtime environment detection.
ACTIVE_CONFIG="base/assets/flutter_assets/config/raichu.yaml"
grep -qxF "$ACTIVE_CONFIG" <<<"$ENTRIES" || {
  echo "❌ stamp-android: donor lacks $ACTIVE_CONFIG" >&2
  exit 1
}
mkdir -p "$WORK/$(dirname "$ACTIVE_CONFIG")"
cp "$ROOT/config/$LANDSCAPE.yaml" "$WORK/$ACTIVE_CONFIG"
(cd "$WORK" && zip -qq "$OUT_ABS" "$ACTIVE_CONFIG")

# --- re-sign -----------------------------------------------------------------
zip -qq -d "$OUT" "META-INF/*" >/dev/null 2>&1 || true
jarsigner -keystore "$ANDROID_KEYSTORE_PATH" \
  -storepass:env ANDROID_KEYSTORE_PASSWORD -keypass:env ANDROID_KEY_PASSWORD \
  -digestalg SHA-256 -sigalg SHA256withRSA \
  "$OUT" "$ANDROID_KEY_ALIAS" >/dev/null

# --- doctor ------------------------------------------------------------------
# Assert every stamped field before this artifact goes anywhere near Play.
bundletool validate --bundle="$OUT" >/dev/null
DUMP=$(bundletool dump manifest --bundle="$OUT")
wants=(
  "package=\"$NEW_ID\""
  "android:versionCode=\"$VERSION_CODE\""
  "android:label=\"$NEW_LABEL\""
  "android:scheme=\"$NEW_ID\""
)
if [ -n "$VERSION_NAME" ]; then wants+=("android:versionName=\"$VERSION_NAME\""); fi
for want in "${wants[@]}"; do
  grep -qF "$want" <<<"$DUMP" || {
    echo "stamp-android doctor: missing $want" >&2
    exit 1
  }
done
if [ "$OLD_ID" != "$NEW_ID" ] && grep -qF "$OLD_ID" <<<"$DUMP"; then
  echo "stamp-android doctor: donor id $OLD_ID still present" >&2
  exit 1
fi
jarsigner -verify "$OUT" | grep -q "jar verified" ||
  {
    echo "stamp-android doctor: signature verification failed" >&2
    exit 1
  }
yq -e ".app.landscape == \"$LANDSCAPE\"" <(unzip -p "$OUT" "$ACTIVE_CONFIG") >/dev/null || {
  echo "❌ stamp-android doctor: baked config is not $LANDSCAPE" >&2
  exit 1
}

echo "✅ stamp-android: $LANDSCAPE — $NEW_ID versionCode=$VERSION_CODE label='$NEW_LABEL'"
