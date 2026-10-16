#!/bin/bash
# ntfs-autorw — EVENT-DRIVEN auto-remounter for NTFS drives on macOS.
# Triggered by launchd WatchPath on /Volumes (fires only when a volume mounts —
# no polling, no idle activity). Ensures every attached NTFS volume is mounted
# read-write at /Volumes/<name> via NTFS-3G (macFUSE), as the console user.
# Also converts Mounty-style ~/.mounty/<name> mounts and revives unmounted volumes.
#
# Uninstall: sudo launchctl bootout system/com.ntfsautorw.daemon
#            sudo rm /Library/LaunchDaemons/com.ntfsautorw.daemon.plist /usr/local/lib/ntfs-autorw.sh

# single-instance lock (RunAtLoad + explicit runs can overlap)
if ! /bin/mkdir /tmp/ntfs-autorw.lock 2>/dev/null; then exit 0; fi
trap '/bin/rmdir /tmp/ntfs-autorw.lock 2>/dev/null' EXIT

NTFS3G=/opt/homebrew/bin/ntfs-3g
[ -x "$NTFS3G" ] || exit 0

CONSOLE_USER=$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null) || exit 0
[ -n "$CONSOLE_USER" ] || exit 0
OWNER=$(/usr/bin/stat -f '%u:%g' "/Users/$CONSOLE_USER" 2>/dev/null) || exit 0
U=${OWNER%%:*}; G=${OWNER##*:}
MOUNTY_BASE="/Users/$CONSOLE_USER/.mounty"

# WatchPath can fire just before FSKit finishes mounting — wait briefly (max ~6s)
n=0
while [ $n -lt 3 ]; do
  /sbin/mount | /usr/bin/grep -qE 'read-only|\.mounty/' && break
  /bin/sleep 2; n=$((n+1))
done

# all NTFS devices attached right now (by filesystem personality, mounted or not)
DEVS=$(/usr/sbin/diskutil list -plist 2>/dev/null | /usr/bin/python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    for dp in d.get("AllDisksAndPartitions", []):
        for p in dp.get("Partitions", []):
            fst = (p.get("FilesystemType") or "").lower()
            ct  = (p.get("Content") or "").lower()
            if "ntfs" in fst or "ntfs" in ct:
                print(p.get("DeviceIdentifier", ""))
except Exception:
    pass' 2>/dev/null)

for dev in $DEVS; do
  vol=$(/usr/sbin/diskutil info "$dev" 2>/dev/null | /usr/bin/awk -F': *' '/Volume Name/{print $2; exit}')
  [ -z "$vol" ] && continue
  cur=$(/sbin/mount | /usr/bin/awk -v d="$dev" '$1==d {print $3}' | /usr/bin/head -1)

  # already mounted read-write at the right place? done.
  if [ "$cur" = "/Volumes/$vol" ]; then
    /sbin/mount | /usr/bin/grep "^$dev on" | /usr/bin/grep -q read-only || continue
  fi

  # unmount current mount (read-only fskit, or Mounty ~/.mounty) — max 5 rounds
  round=0
  while [ -n "$cur" ] && [ $round -lt 5 ]; do
    /usr/sbin/diskutil unmount force "$cur" >/dev/null 2>&1
    /bin/sleep 1
    cur=$(/sbin/mount | /usr/bin/awk -v d="$dev" '$1==d {print $3}' | /usr/bin/head -1)
    round=$((round+1))
  done
  [ -n "$cur" ] && { /usr/bin/logger -t ntfs-autorw "could not unmount $vol ($cur)"; continue; }

  /bin/mkdir -p "/Volumes/$vol"
  if "$NTFS3G" "$dev" "/Volumes/$vol" -o local,allow_other,uid=$U,gid=$G,auto_xattr >/dev/null 2>&1; then
    /usr/bin/logger -t ntfs-autorw "$vol -> /Volumes/$vol read-write ($dev)"
  else
    /usr/bin/logger -t ntfs-autorw "FAILED remounting $vol at /Volumes/$vol (check macFUSE)"
  fi
done
exit 0
