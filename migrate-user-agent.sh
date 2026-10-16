#!/bin/bash
# migrate-user-agent.sh — one-time migration: removes the system LaunchDaemon and
# replaces it with a user-level LaunchAgent + NOPASSWD sudoers entry for exactly
# one script (/usr/local/lib/ntfs-autorw.sh). Runs the mount in the user's session
# context (required on macOS 26/27 — system-domain root gets EPERM on raw opens).
#
# Usage: sudo bash migrate-user-agent.sh
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then echo "Run with sudo: sudo bash $0"; exit 1; fi
DIR="$(cd "$(dirname "$0")" && pwd)"
CONSOLE_USER=$(/usr/bin/stat -f '%Su' /dev/console)
CONSOLE_UID=$(/usr/bin/stat -f '%u' /dev/console)
LABEL_SYS="com.ntfsautorw.daemon"
LABEL_USER="com.ntfsautorw.watcher"
SUDOERS="/etc/sudoers.d/ntfs-autorw"
SCRIPT="/usr/local/lib/ntfs-autorw.sh"

[ -x "$SCRIPT" ] || { echo "ERROR: $SCRIPT missing — run install.sh first"; exit 1; }

echo ">> 1/4 removing system LaunchDaemon (if present)..."
launchctl bootout system/$LABEL_SYS 2>/dev/null || true
rm -f "/Library/LaunchDaemons/$LABEL_SYS.plist"

echo ">> 2/4 writing NOPASSWD sudoers entry (script only, no args)..."
echo "$CONSOLE_USER ALL=(root) NOPASSWD: $SCRIPT" > "$SUDOERS"
/usr/sbin/chown root:wheel "$SUDOERS"
/bin/chmod 0440 "$SUDOERS"
/usr/sbin/visudo -c -f "$SUDOERS"

echo ">> 3/4 installing user watcher..."
/usr/bin/install -m 755 "$DIR/ntfs-autorw-watch.sh" "/Users/$CONSOLE_USER/.local/bin/ntfs-autorw-watch.sh"
/usr/sbin/chown "$CONSOLE_USER" "/Users/$CONSOLE_USER/.local/bin/ntfs-autorw-watch.sh"
launchctl bootout "gui/$CONSOLE_UID/$LABEL_USER" 2>/dev/null || true
rm -f "/Users/$CONSOLE_USER/Library/LaunchAgents/$LABEL_USER.plist"
/usr/bin/install -m 644 "$DIR/com.ntfsautorw.watcher.plist" "/Users/$CONSOLE_USER/Library/LaunchAgents/$LABEL_USER.plist"
/usr/sbin/chown "$CONSOLE_USER" "/Users/$CONSOLE_USER/Library/LaunchAgents/$LABEL_USER.plist"
launchctl bootstrap "gui/$CONSOLE_UID" "/Users/$CONSOLE_USER/Library/LaunchAgents/$LABEL_USER.plist"

echo ">> 4/4 triggering first run..."
launchctl kickstart "gui/$CONSOLE_UID/$LABEL_USER" 2>/dev/null || true

echo
echo "✅ Migration complete. NTFS volumes auto-remount read-write at /Volumes,"
echo "   running in your session context. Uninstall:"
echo "     launchctl bootout gui/$CONSOLE_UID/$LABEL_USER"
echo "     rm /Users/$CONSOLE_USER/Library/LaunchAgents/$LABEL_USER.plist /Users/$CONSOLE_USER/.local/bin/ntfs-autorw-watch.sh"
echo "     sudo rm $SUDOERS $SCRIPT"
