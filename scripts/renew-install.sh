#!/bin/zsh
# Keeps TME working on your iPhone with a free Apple ID.
#
# Free signing lasts 7 days. When the copy on the phone has 3 days or less
# left, this gets fresh profiles from Apple, rebuilds, and reinstalls over
# Wi-Fi (your data is kept). Otherwise it does nothing. Safe to run any time;
# scripts/install-renew-agent.sh runs it every 6 hours.
#
# Needs: Xcode signed in to your Apple ID, and the iPhone paired with Xcode
# and on the same Wi-Fi as the Mac.
#
# Options (environment variables):
#   RENEW_WITHIN_DAYS=3   renew when this many days or fewer are left
#   TME_DEVICE=<udid>     which iPhone (default: the first paired one)
#   FORCE=1               renew and reinstall now

set -u
setopt pipefail

REPO="${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
PROFILES="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
STATE_DIR="$HOME/Library/Application Support/tme-renew"
STATE_FILE="$STATE_DIR/installed-expiry"
LOG="$HOME/Library/Logs/tme-renew.log"
DERIVED="$REPO/build/RenewDerivedData"
RENEW_WITHIN_DAYS="${RENEW_WITHIN_DAYS:-3}"
mkdir -p "$STATE_DIR" "${LOG:h}"

log() { print -r -- "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }
notify() { /usr/bin/osascript -e "display notification \"$1\" with title \"TME\"" >/dev/null 2>&1 || true; }
fail() { log "FAILED: $1"; notify "$1"; exit 1; }

# Signing settings, from the same file Xcode uses.
setting() { sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*([^[:space:]]+).*/\1/p" "$REPO/Config/Signing.xcconfig" | tail -1; }
TEAM="$(setting DEVELOPMENT_TEAM)"
PREFIX="$(setting BUNDLE_ID_PREFIX)"
[[ -n "$TEAM" && -n "$PREFIX" ]] || fail "Config/Signing.xcconfig is missing DEVELOPMENT_TEAM or BUNDLE_ID_PREFIX."
BUNDLE_IDS=("$PREFIX.tme" "$PREFIX.tme.widgets")

now=$(date +%s)
days_left() { # "1 day", "6 days"
  local n=$(( ($1 - now) / 86400 ))
  (( n == 1 )) && print "1 day" || print "$n days"
}
expiry_of() { # expiry (epoch seconds) of a .mobileprovision file
  local d
  d=$(security cms -D -i "$1" 2>/dev/null | plutil -extract ExpirationDate raw - 2>/dev/null) || return 1
  date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$d" +%s
}

# 1. How long does the copy on the phone have left?
installed_expiry=$(cat "$STATE_FILE" 2>/dev/null || print 0)
if [[ "${FORCE:-0}" != 1 ]] && (( installed_expiry - now > RENEW_WITHIN_DAYS * 86400 )); then
  log "OK: the app on the phone has $(days_left $installed_expiry) left."
  exit 0
fi

# 2. Is the phone reachable?
device="${TME_DEVICE:-}"
if [[ -z "$device" ]]; then
  json="$(mktemp)"
  xcrun devicectl list devices --json-output "$json" >/dev/null 2>&1
  device=$(/usr/bin/python3 -c '
import json, sys
for d in json.load(open(sys.argv[1]))["result"]["devices"]:
    hw, conn = d.get("hardwareProperties", {}), d.get("connectionProperties", {})
    if hw.get("platform") == "iOS" and hw.get("reality") == "physical" and conn.get("pairingState") == "paired":
        print(hw.get("udid") or d["identifier"]); break
' "$json" 2>/dev/null)
  rm -f "$json"
fi
if [[ -z "$device" ]] || ! xcrun devicectl device info details --device "$device" --timeout 45 >/dev/null 2>&1; then
  msg="Can't reach your iPhone to renew TME."
  if (( installed_expiry > 0 )); then
    msg="$msg It stops opening in $(days_left $installed_expiry). Put the phone on the Mac's Wi-Fi."
    (( installed_expiry - now < 86400 * 2 )) && notify "$msg"
  fi
  log "WAITING: $msg"
  exit 0
fi

# 3. Profiles close to expiry are moved aside so Xcode fetches fresh 7-day ones.
mkdir -p "$STATE_DIR/old-profiles"
for f in "$PROFILES"/*.mobileprovision(N); do
  app_id=$(security cms -D -i "$f" 2>/dev/null | plutil -extract Entitlements.application-identifier raw - 2>/dev/null) || continue
  for id in $BUNDLE_IDS; do
    if [[ "$app_id" == "$TEAM.$id" ]]; then
      exp=$(expiry_of "$f") || continue
      if [[ "${FORCE:-0}" == 1 ]] || (( exp - now <= RENEW_WITHIN_DAYS * 86400 )); then
        mv "$f" "$STATE_DIR/old-profiles/" && log "Renewing profile for $id (it expired or expires soon)."
      fi
    fi
  done
done

# 4. Build, signed with fresh profiles.
log "Building..."
build_log="$STATE_DIR/last-build.log"
if ! xcodebuild -project "$REPO/TME.xcodeproj" -scheme TME -configuration Debug \
     -destination "id=$device" -derivedDataPath "$DERIVED" \
     -allowProvisioningUpdates -allowProvisioningDeviceRegistration build > "$build_log" 2>&1; then
  if grep -qE "No Accounts|Sign in|not signed in|authentication" "$build_log"; then
    fail "Couldn't renew TME: Xcode is signed out. Open Xcode → Settings → Apple Accounts and sign in."
  fi
  fail "Couldn't renew TME: the build failed. Details: $build_log"
fi

# 5. Install over Wi-Fi.
app="$DERIVED/Build/Products/Debug-iphoneos/TME.app"
if ! xcrun devicectl device install app --device "$device" "$app" >> "$build_log" 2>&1; then
  fail "Couldn't install the renewed TME on your iPhone. Details: $build_log"
fi

# 6. Remember when this copy expires (the earliest of the app and its widget add-on).
expiry=$(expiry_of "$app/embedded.mobileprovision") || fail "Installed, but couldn't read the new expiry date."
for ext in "$app"/PlugIns/*.appex(N); do
  e=$(expiry_of "$ext/embedded.mobileprovision") && (( e < expiry )) && expiry=$e
done
print "$expiry" > "$STATE_FILE"
log "RENEWED: installed on the phone, good until $(date -r $expiry '+%d %b %H:%M')."
