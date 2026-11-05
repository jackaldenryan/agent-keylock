#!/usr/bin/env bash
# Build, sign, notarize, and package the public macOS binary.
# Run this in a Terminal you control, after the Developer ID certificate
# and the notarytool profile exist. This script does not create either.
set -euo pipefail

version="${1:-0.1.0}"
root="$(cd "$(dirname "$0")/.." && pwd)"
profile="${NOTARY_PROFILE:-agent-keylock}"
tap_cask="${TAP_CASK:-${root}/../homebrew-tap/Casks/agent-keylock.rb}"
dist="${root}/dist"
stage="$(mktemp -d)"
archive="${dist}/agent-keylock-${version}-macos.zip"
cleanup() { rm -rf "$stage"; }
trap cleanup EXIT

identity="$(/usr/bin/security find-identity -v -p codesigning | /usr/bin/sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | /usr/bin/head -1)"
if [[ -z "$identity" ]]; then
  echo "No Developer ID Application certificate is installed." >&2
  echo "Create one at https://developer.apple.com/account/resources/certificates/add" >&2
  echo "Choose Developer ID Application, upload a certificate request, then double-click the downloaded certificate." >&2
  exit 1
fi

if ! /usr/bin/xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
  echo "No notarytool profile named ${profile}." >&2
  echo "In your own Terminal, create an app-specific password at https://account.apple.com and then run:" >&2
  echo "  xcrun notarytool store-credentials ${profile} --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID" >&2
  exit 1
fi

cd "$root"
swift build -c release --product keylock
mkdir -p "$dist" "$stage/skills"
cp -f .build/release/keylock "$stage/keylock"
cp -R skills/keybank "$stage/skills/keybank"
chmod 755 "$stage/keylock"

/usr/bin/codesign --force --sign "$identity" \
  --options runtime \
  --timestamp \
  --identifier com.apikeylock.keylock \
  "$stage/keylock"
/usr/bin/codesign --verify --strict --verbose=2 "$stage/keylock"

rm -f "$archive"
(cd "$stage" && /usr/bin/zip -r -X "$archive" keylock skills)
/usr/bin/xcrun notarytool submit "$archive" --keychain-profile "$profile" --wait
# Apple can notarize a zip, but stapler cannot attach a ticket to one.
# The ticket stays online, which is enough for a downloaded release.

checksum="$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print $1}')"
echo "archive: $archive"
echo "sha256: $checksum"
echo "signed by: $identity"

if [[ -f "$tap_cask" ]]; then
  /usr/bin/python3 - "$tap_cask" "$version" "$checksum" << 'PY'
import pathlib, re, sys
path, version, checksum = sys.argv[1:]
file = pathlib.Path(path)
text = file.read_text()
text = re.sub(r'^  version ".*"$', f'  version "{version}"', text, count=1, flags=re.M)
text = re.sub(r'^  sha256 ".*"$', f'  sha256 "{checksum}"', text, count=1, flags=re.M)
file.write_text(text)
PY
  echo "updated $tap_cask"
else
  echo "cask not found at $tap_cask"
fi

echo
echo "Publish from your own Terminal:"
echo "  cd \"$root\""
echo "  git tag v${version}"
echo "  git push origin v${version}"
echo "  gh release create v${version} \"$archive\" --title \"v${version}\" --notes \"Signed macOS release.\""
echo "  cd \"$(dirname "$tap_cask")/..\""
echo "  git add Casks/agent-keylock.rb && git commit -m \"Publish agent-keylock ${version}.\" && git push"
