#!/bin/bash
# Manual NTFS read-write remount (no daemon needed). Usage: sudo bash mount-ntfs-rw.sh <VolumeName>
set -u
VOL="${1:-}"
[ -z "$VOL" ] && { echo "Usage: sudo bash $0 <VolumeName>"; exit 1; }
NTFS3G=/opt/homebrew/bin/ntfs-3g
[ -x "$NTFS3G" ] || { echo "ntfs-3g missing — see README requirements"; exit 1; }

CONSOLE_USER=$(/usr/bin/stat -f '%Su' /dev/console)
OWNER=$(/usr/bin/stat -f '%u:%g' "/Users/$CONSOLE_USER")
U=${OWNER%%:*}; G=${OWNER##*:}

DEV=$(/usr/sbin/diskutil info "$VOL" 2>/dev/null | /usr/bin/awk -F': *' '/Device Node/{print $2; exit}')
[ -z "$DEV" ] && { echo "ERROR: volume '$VOL' not found"; exit 1; }

echo ">> step 1/3: unmounting existing mounts of $VOL ..."
for M in "/Volumes/$VOL" "/Users/$CONSOLE_USER/.mounty/$VOL"; do
  if /sbin/mount | /usr/bin/grep -q " on $M "; then
    /usr/sbin/diskutil unmount force "$M" >/dev/null 2>&1 || { echo "FAILED: could not unmount $M"; exit 1; }
    echo "   unmounted $M"
  fi
done

echo ">> step 2/3: preparing mount point ..."
/bin/mkdir -p "/Volumes/$VOL"

echo ">> step 3/3: mounting via ntfs-3g (uid=$U) ..."
"$NTFS3G" "$DEV" "/Volumes/$VOL" -o local,allow_other,uid=$U,gid=$G,auto_xattr
RC=$?
[ $RC -ne 0 ] && { echo "FAILED: ntfs-3g exited $RC (if macOS showed a 'System software blocked' prompt, approve macFUSE in Privacy & Security, restart if asked, then retry)"; exit $RC; }
echo "=== RW MOUNT OK: $VOL is read-write at /Volumes/$VOL ==="
