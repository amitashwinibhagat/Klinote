#!/usr/bin/env bash
# Build, sign and package Klinote for handing to somebody else.
#
# Unsigned or ad-hoc builds are fine on the machine that made them and useless
# anywhere else: Gatekeeper refuses them, and a hardened runtime build without
# the audio-input entitlement cannot record at all. So a release build is
# signed with a Developer ID, hardened, and timestamped. Notarization is
# attempted when credentials are present, because a Developer ID signature
# alone still makes a downloaded copy show "Apple could not verify".
#
#   scripts/release.sh                 # sign with the Developer ID in the keychain
#   NOTARY_PROFILE=klinote scripts/release.sh   # ...and notarize
#
# Notarization needs a stored profile first:
#   xcrun notarytool store-credentials klinote --apple-id ... --team-id ...
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$root/apps/Klinote"
dist="$root/dist"
version="$(sed -n 's/.*MARKETING_VERSION: *"\(.*\)"/\1/p' "$app_dir/project.yml" | head -1)"

if [ -z "$version" ]; then
  echo "::error::could not read MARKETING_VERSION from project.yml"
  exit 1
fi

# Klinote ships from DataDab LLP. The team is pinned rather than "whichever
# Developer ID happens to be first in the keychain", because the keychain lists
# identities in no particular order and a second Developer ID — a personal one,
# or another company's — would silently sign a release as the wrong legal
# entity. Override with RELEASE_TEAM_ID only when the product really does move.
expected_team="${RELEASE_TEAM_ID:-THC77ZVYVB}"

identity="${CODE_SIGN_IDENTITY:-}"
if [ -z "$identity" ]; then
  identity="$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)"/\1/p' \
    | grep "($expected_team)" | head -1)"
fi
if [ -z "$identity" ]; then
  echo "::error::no 'Developer ID Application' certificate for team $expected_team."
  echo "          Klinote is signed as DataDab LLP; a release from another"
  echo "          team would be attributed to the wrong entity. If the product"
  echo "          really has moved, set RELEASE_TEAM_ID and update"
  echo "          docs/engineering/RELEASING.md."
  exit 1
fi

team="$(sed -n 's/.*(\([A-Z0-9]*\))$/\1/p' <<<"$identity")"
echo "building Klinote $version"
echo "  identity: $identity"
echo "  team:     $team"

# The project is generated, not committed.
(cd "$app_dir" && xcodegen generate >/dev/null)

# ARCHS=arm64 matches project.yml: the Rust engine is built for the host by
# cargo, so a universal binary would need a second cargo target rather than a
# second arch flag.
#
# CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO because Xcode otherwise injects
# `get-task-allow`, the debugging entitlement, which lets a debugger attach to
# a shipped app and has no business in a release.
(cd "$app_dir" && xcodebuild \
  -project Klinote.xcodeproj \
  -scheme Klinote \
  -configuration Release \
  -derivedDataPath "$root/build/DerivedData" \
  ARCHS=arm64 \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$identity" \
  DEVELOPMENT_TEAM="$team" \
  ENABLE_HARDENED_RUNTIME=YES \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
  build)

app="$root/build/DerivedData/Build/Products/Release/Klinote.app"
[ -d "$app" ] || { echo "::error::no app at $app"; exit 1; }

echo
echo "verifying the signature"
codesign --verify --deep --strict --verbose=2 "$app"

# Notarization judges every executable in the bundle, not just the app, and the
# app can verify perfectly while a nested helper does not. That is worth a local
# check rather than a two-minute round trip to Apple: the first notarized build
# came back Invalid solely because `scribe-llm` was ad-hoc signed, untimestamped
# and not hardened.
nested_failed=0
while IFS= read -r nested; do
  relative="${nested#"$app"/}"
  info="$(codesign -dv --verbose=4 "$nested" 2>&1 || true)"
  problem=""
  grep -q "Authority=Developer ID Application" <<<"$info" \
    || problem="not signed with a Developer ID"
  grep -q "^Timestamp=" <<<"$info" \
    || problem="${problem:+$problem; }no secure timestamp"
  grep -qE "flags=0x[0-9a-f]+\(runtime\)" <<<"$info" \
    || problem="${problem:+$problem; }hardened runtime not enabled"
  if [ -n "$problem" ]; then
    echo "::error::$relative — $problem"
    nested_failed=1
  else
    echo "  $relative: ok"
  fi
done < <(find "$app/Contents/MacOS" -type f -perm -u+x)
if [ "$nested_failed" -ne 0 ]; then
  echo "          Notarization will reject the archive. See RELEASING.md."
  exit 1
fi
codesign -dv --verbose=4 "$app" 2>&1 | grep -E "Authority|TeamIdentifier|Timestamp|flags" || true
echo "  entitlements:"
codesign -d --entitlements - --xml "$app" 2>/dev/null \
  | plutil -convert xml1 -o - - 2>/dev/null | grep -E "<key>|<true|<false" | sed 's/^/    /' || true

mkdir -p "$dist"
zip="$dist/Klinote-$version.zip"
rm -f "$zip"
# ditto, not zip: it preserves the bundle's metadata and the signature.
ditto -c -k --keepParent "$app" "$zip"
echo
echo "packaged: $zip ($(du -h "$zip" | cut -f1))"

if [ -n "${NOTARY_PROFILE:-}" ]; then
  echo
  echo "notarizing (this can take a few minutes)"
  xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  rm -f "$zip"
  ditto -c -k --keepParent "$app" "$zip"
  echo "notarized and stapled: $zip"
else
  echo
  echo "NOT notarized. A downloaded copy will say Apple could not verify it."
  echo "To fix, store credentials once and re-run:"
  echo "  xcrun notarytool store-credentials klinote --apple-id <id> --team-id $team"
  echo "  NOTARY_PROFILE=klinote scripts/release.sh"
fi
