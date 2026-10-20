#!/bin/zsh
# Publishes a version of TME for people who install it with SideStore, which
# needs no Mac (README → "Without a Mac").
#
# Builds TME.ipa from your latest commit (uncommitted changes are left out)
# and creates GitHub release v<version> with:
#   TME.ipa      the app, unsigned; SideStore signs it with each person's Apple ID
#   source.json  the SideStore source that lists it
#   icon.png     the icon SideStore shows
# The source's address never changes, so people add it once and SideStore
# offers them every new version:
#   https://github.com/codeitkrishna/track-my-expenses/releases/latest/download/source.json
#
#   scripts/release.sh 0.2 "What's new in this version"
#   BUILD_ONLY=1 scripts/release.sh 0.2    build into build/release/ without publishing
#
# Needs: Xcode, and the GitHub CLI signed in (gh auth login).

set -eu
setopt pipefail

REPO="${0:A:h:h}"
GITHUB_REPO="codeitkrishna/track-my-expenses"
# The app's ID in every release. Never change it: SideStore would see a new
# app, and people would lose their data when they update.
BUNDLE_ID_PREFIX="io.github.codeitkrishna"
OUT="$REPO/build/release"
SOURCE_URL="https://github.com/$GITHUB_REPO/releases/latest/download/source.json"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ICTOOL="$DEVELOPER_DIR/../Applications/Icon Composer.app/Contents/Executables/ictool"

fail() { print -u2 -r -- "release: $1"; exit 1; }

VERSION="${1:-}"
NOTES="${2:-}"
[[ "$VERSION" =~ '^[0-9]+(\.[0-9]+){1,2}$' ]] || fail "usage: scripts/release.sh <version, like 0.2> [what's new]"
TAG="v$VERSION"
COMMIT="$(git -C "$REPO" rev-parse HEAD)"

# 1. Before building, make sure it can be published.
if [[ "${BUILD_ONLY:-0}" != 1 ]]; then
  gh auth status >/dev/null 2>&1 || fail "Sign in to GitHub first: gh auth login"
  if gh release view "$TAG" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
    fail "Release $TAG already exists. Use a higher version."
  fi
  gh api "repos/$GITHUB_REPO/commits/$COMMIT" --silent 2>/dev/null \
    || fail "Your latest commit isn't on GitHub. Push it first (git push); the release is built from it."
fi
[[ -z "$(git -C "$REPO" status --porcelain)" ]] || print "Note: uncommitted changes aren't included."

# 2. Build the latest commit, unsigned.
print "Building TME $VERSION from commit ${COMMIT[1,7]}..."
rm -rf "$OUT"
mkdir -p "$OUT/src"
git -C "$REPO" archive "$COMMIT" | tar -x -C "$OUT/src"
xcodebuild -project "$OUT/src/TME.xcodeproj" -scheme TME -configuration Release \
  -destination "generic/platform=iOS" -derivedDataPath "$OUT/DerivedData" \
  -archivePath "$OUT/TME.xcarchive" archive \
  CODE_SIGNING_ALLOWED=NO BUNDLE_ID_PREFIX="$BUNDLE_ID_PREFIX" MARKETING_VERSION="$VERSION" \
  > "$OUT/build.log" 2>&1 || fail "The build failed. Details: $OUT/build.log"

APP="$OUT/TME.xcarchive/Products/Applications/TME.app"
plist() { plutil -extract "$2" raw "$1/Info.plist"; }
[[ "$(plist "$APP" CFBundleIdentifier)" == "$BUNDLE_ID_PREFIX.tme" ]] || fail "The app was built with the wrong bundle ID."
[[ "$(plist "$APP" CFBundleShortVersionString)" == "$VERSION" ]] || fail "The app was built with the wrong version."
[[ -d "$APP/PlugIns/TMEWidgets.appex" ]] || fail "The app is missing its widget, which shows the category banner."

mkdir "$OUT/Payload"
cp -R "$APP" "$OUT/Payload/"
(cd "$OUT" && zip -qry TME.ipa Payload)

if ! "$ICTOOL" "$OUT/src/TME/Resources/AppIcon.icon" --export-image --output-file "$OUT/icon.png" \
     --platform iOS --rendition Default --width 512 --height 512 --scale 1 >/dev/null 2>&1; then
  cp "$APP/AppIcon60x60@2x.png" "$OUT/icon.png"  # smaller, but always there
fi

# 3. The SideStore source. SideStore checks the downloaded app against it
# (bundle ID, version, size, SHA-256), so every value comes from the build.
/usr/bin/python3 - "$OUT" "$APP" "$GITHUB_REPO" "$TAG" "$NOTES" <<'PY'
import datetime, glob, hashlib, json, plistlib, sys

out, app, repo, tag, notes = sys.argv[1:]
info = plistlib.load(open(f"{app}/Info.plist", "rb"))
ipa = open(f"{out}/TME.ipa", "rb").read()
version = info["CFBundleShortVersionString"]

# SideStore won't install an app that asks for privacy permissions its source doesn't declare.
privacy = {}
for path in [f"{app}/Info.plist", *glob.glob(f"{app}/PlugIns/*.appex/Info.plist")]:
    for key, value in plistlib.load(open(path, "rb")).items():
        if key.startswith("NS") and key.endswith("UsageDescription"):
            privacy[key] = value

files = f"https://github.com/{repo}/releases/download/{tag}"
subtitle = "An expense tracker that logs your bank SMS"
description = (
    "A personal expense tracker for iPhone, built for people who won't type in every expense.\n\n"
    "• Bank SMS log themselves through a Shortcuts automation.\n"
    "• A banner asks for the category; once a merchant is filed, its later payments are filed automatically.\n"
    "• Add expenses and income from anywhere with Shortcuts, AssistiveTouch, Back Tap or Siri.\n"
    "• Everything stays on your iPhone. No accounts, no servers, no bank logins."
)
source = {
    "name": "TME",
    "identifier": "io.github.codeitkrishna.tme.source",
    "subtitle": subtitle,
    "description": description,
    "iconURL": f"{files}/icon.png",
    "website": f"https://github.com/{repo}",
    "apps": [{
        "name": "TME",
        "bundleIdentifier": info["CFBundleIdentifier"],
        "developerName": "codeitkrishna",
        "subtitle": subtitle,
        "localizedDescription": description,
        "iconURL": f"{files}/icon.png",
        "versions": [{
            "version": version,
            "buildVersion": info["CFBundleVersion"],
            "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "localizedDescription": notes or f"TME {version}",
            "downloadURL": f"{files}/TME.ipa",
            "size": len(ipa),
            "sha256": hashlib.sha256(ipa).hexdigest(),
            "minOSVersion": info["MinimumOSVersion"],
        }],
        "appPermissions": {"entitlements": [], "privacy": privacy},
    }],
}
with open(f"{out}/source.json", "w") as f:
    json.dump(source, f, indent=2, ensure_ascii=False)
PY

if [[ "${BUILD_ONLY:-0}" == 1 ]]; then
  print "Built $OUT/TME.ipa and source.json (not published)."
  exit 0
fi

# 4. Publish. gh uploads the files before the release goes public.
print "Publishing $TAG..."
gh release create "$TAG" "$OUT/TME.ipa" "$OUT/source.json" "$OUT/icon.png" \
  --repo "$GITHUB_REPO" --target "$COMMIT" --title "TME $VERSION" \
  --notes "${NOTES:+$NOTES

}Install it on your iPhone without a Mac: https://github.com/$GITHUB_REPO#without-a-mac" >/dev/null

listed="$(curl -fsSL "$SOURCE_URL" | plutil -extract apps.0.versions.0.version raw - 2>/dev/null || true)"
if [[ "$listed" == "$VERSION" ]]; then
  print "Published TME $VERSION. SideStore will offer it to everyone who added $SOURCE_URL"
else
  print "Published $TAG, but the SideStore source doesn't list $VERSION yet. Check https://github.com/$GITHUB_REPO/releases"
fi
