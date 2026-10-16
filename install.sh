#!/bin/bash
# ntfs-autorw installer — auto-remount NTFS drives read-write at /Volumes on macOS.
# Requirements: macFUSE + NTFS-3G (see README).
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then echo "Run with sudo: sudo bash install.sh"; exit 1; fi
DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.ntfsautorw.daemon"
PLIST="/Library/LaunchDaemons/$LABEL.plist"

if [ ! -x /opt/homebrew/bin/ntfs-3g ]; then
  echo "ERROR: ntfs-3g not found. First run:"
  echo "  brew install --cask macfuse"
  echo "  brew install gromgit/fuse/ntfs-3g-mac"
  echo "Then approve macFUSE in System Settings > Privacy & Security (restart if asked), and re-run this installer."
  exit 1
fi

launchctl bootout system/$LABEL 2>/dev/null || true
/usr/bin/install -m 755 "$DIR/ntfs-autorw.sh" /usr/local/lib/ntfs-autorw.sh
/usr/bin/install -m 644 "$DIR/com.ntfsautorw.daemon.plist" "$PLIST"
launchctl bootstrap system "$PLIST"

echo
echo "✅ Installed. NTFS volumes now auto-remount read-write at /Volumes when they mount."
echo "   Test: unplug + replug an NTFS drive (or run: sudo /usr/local/lib/ntfs-autorw.sh)."
echo "   Uninstall: sudo bash \"$DIR/uninstall.sh\""
