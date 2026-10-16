#!/bin/bash
# ntfs-autorw uninstaller — removes the daemon; existing read-write mounts stay until unplug/reboot.
set -euo pipefail
if [ "$(id -u)" -ne 0 ]; then echo "Run with sudo: sudo bash uninstall.sh"; exit 1; fi
launchctl bootout system/com.ntfsautorw.daemon 2>/dev/null || true
rm -f /Library/LaunchDaemons/com.ntfsautorw.daemon.plist /usr/local/lib/ntfs-autorw.sh
echo "✅ Removed. NTFS volumes will mount read-only (macOS default) again."
