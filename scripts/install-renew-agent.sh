#!/bin/zsh
# Runs scripts/renew-install.sh every 6 hours (and when the Mac wakes) so the
# free-signed app on your iPhone never reaches its 7-day limit.
#
#   scripts/install-renew-agent.sh            turn it on
#   scripts/install-renew-agent.sh --remove   turn it off
#
# Log: ~/Library/Logs/tme-renew.log

set -eu
REPO="${0:A:h:h}"
LABEL="local.tme.renew"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true

if [[ "${1:-}" == "--remove" ]]; then
  rm -f "$PLIST"
  print "Turned off automatic renewal."
  exit 0
fi

mkdir -p "${PLIST:h}" "$HOME/Library/Logs"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/zsh</string>
        <string>$REPO/scripts/renew-install.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>21600</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/tme-renew.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/tme-renew.log</string>
</dict>
</plist>
EOF

launchctl bootstrap "$DOMAIN" "$PLIST"
print "Automatic renewal is on. It checks every 6 hours; log: ~/Library/Logs/tme-renew.log"
