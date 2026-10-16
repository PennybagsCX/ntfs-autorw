#!/bin/bash
# ntfs-autorw — EVENT-DRIVEN auto-remounter for NTFS drives on macOS.
# Triggered by launchd WatchPath on /Volumes (fires only when a volume mounts —
# no polling, no idle activity). Ensures every attached NTFS volume is mounted
# read-write at /Volumes/<name> via NTFS-3G (macFUSE), as the console user.
# Also converts Mounty-style ~/.mounty/<name> mounts and revives unmounted volumes.
#
# Uninstall: sudo launchctl bootout system/com.ntfsautorw.daemon
#            sudo rm /Library/LaunchDaemons/com.ntfsautorw.daemon.plist /usr/local/lib/ntfs-autorw.sh

# single-instance lock (RunAtLoad + explicit runs can overlap), with stale-lock self-heal
if ! /bin/mkdir /tmp/ntfs-autorw.lock 2>/dev/null; then
  # lock exists — if no actual script instance is running, it's stale from a killed run
  /usr/bin/pgrep -f "[n]tfs-autorw.sh" >/dev/null 2>&1 || /bin/rmdir /tmp/ntfs-autorw.lock 2>/dev/null
  /bin/mkdir /tmp/ntfs-autorw.lock 2>/dev/null || exit 0
fi
trap '/bin/rmdir /tmp/ntfs-autorw.lock 2>/dev/null' EXIT

NTFS3G=/opt/homebrew/bin/ntfs-3g
[ -x "$NTFS3G" ] || exit 0

# launchd root context has empty TMPDIR and a minimal PATH; macFUSE helpers need both
export TMPDIR="${TMPDIR:-/tmp}"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

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

# all NTFS devices attached right now (mounted or not): data partitions with a
# volume name, confirmed by diskutil's "File System Personality" check
DEVS=$(
  /usr/sbin/diskutil list -plist 2>/dev/null | /usr/bin/plutil -convert json -o - - 2>/dev/null | /usr/bin/python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    for dp in d.get("AllDisksAndPartitions", []):
        for p in dp.get("Partitions", []):
            if p.get("VolumeName") or "basic data" in (p.get("Content") or "").lower():
                print(p.get("DeviceIdentifier", ""))
except Exception as e:
    sys.stderr.write("ntfs-autorw detection error: %s\n" % e)' 2>/dev/null
)
/usr/bin/logger -t ntfs-autorw "scan: $(/bin/echo "$DEVS" | /usr/bin/grep -c .) candidate device(s) [TMPDIR=$TMPDIR]"

for dev in $DEVS; do
  /usr/bin/logger -t ntfs-autorw "scan: candidate $dev"
  /usr/sbin/diskutil info "$dev" 2>/dev/null | /usr/bin/grep -q "File System Personality:.*NTFS" || { /usr/bin/logger -t ntfs-autorw "scan: $dev not NTFS, skip"; continue; }
  vol=$(/usr/sbin/diskutil info "$dev" 2>/dev/null | /usr/bin/awk -F': *' '/Volume Name/{print $2; exit}')
  [ -z "$vol" ] && continue
  cur=$(/sbin/mount | /usr/bin/awk -v d="/dev/$dev" '$1==d {print $3}' | /usr/bin/head -1)

  # already mounted read-write at the right place? done.
  if [ "$cur" = "/Volumes/$vol" ]; then
    /sbin/mount | /usr/bin/grep "^$dev on" | /usr/bin/grep -q read-only || continue
  fi

  # unmount current mount (read-only fskit, or Mounty ~/.mounty) — max 5 rounds
  round=0
  while [ -n "$cur" ] && [ $round -lt 5 ]; do
    /usr/sbin/diskutil unmount force "$cur" >/dev/null 2>&1
    /bin/sleep 1
    cur=$(/sbin/mount | /usr/bin/awk -v d="/dev/$dev" '$1==d {print $3}' | /usr/bin/head -1)
    round=$((round+1))
  done
  [ -n "$cur" ] && { /usr/bin/logger -t ntfs-autorw "could not unmount $vol ($cur)"; continue; }

  # FSKit-era unmounts can tear down / renumber the device node — re-resolve by
  # volume name and wait for the node to exist before handing it to ntfs-3g
  tries=0; NEWDEV=""
  while [ -z "$NEWDEV" ] && [ $tries -lt 10 ]; do
    NEWDEV=$(/usr/sbin/diskutil info "$vol" 2>/dev/null | /usr/bin/awk -F': *' '/Device Node/{print $2; exit}')
    if [ -n "$NEWDEV" ] && [ -e "$NEWDEV" ]; then break; fi
    NEWDEV=""; /bin/sleep 1; tries=$((tries+1))
  done
  if [ -z "$NEWDEV" ]; then
    /usr/bin/logger -t ntfs-autorw "device node for $vol disappeared after unmount; giving up"
    continue
  fi
  dev="$NEWDEV"

  /bin/mkdir -p "/Volumes/$vol"
  # FSKit holds an exclusive claim on the device for a few seconds after unmount —
  # retry with a freshly resolved device node until it releases (or give up)
  ERR="pending"; ok=0; att=0
  while [ $ok -eq 0 ] && [ $att -lt 8 ]; do
    NEWDEV=$(/usr/sbin/diskutil info "$vol" 2>/dev/null | /usr/bin/awk -F': *' '/Device Node/{print $2; exit}')
    if [ -n "$NEWDEV" ] && [ -e "$NEWDEV" ]; then
      ERR=$("$NTFS3G" "$NEWDEV" "/Volumes/$vol" -o local,allow_other,uid=$U,gid=$G,auto_xattr 2>&1 >/dev/null)
      [ -z "$ERR" ] && ok=1
    fi
    att=$((att+1)); [ $ok -eq 0 ] && /bin/sleep 1
  done
  if [ $ok -eq 1 ]; then
    /usr/bin/logger -t ntfs-autorw "$vol -> /Volumes/$vol read-write"
  else
    /usr/bin/logger -t ntfs-autorw "FAILED remounting $vol after $att attempts: $ERR"
  fi
done
exit 0
