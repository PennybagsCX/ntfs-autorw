#!/bin/bash
# ntfs-autorw-watch — user-level watcher. Fires on /Volumes changes (launchd
# WatchPaths) and at login; delegates the privileged remount through the
# NOPASSWD sudoers entry for /usr/local/lib/ntfs-autorw.sh.
exec /usr/bin/sudo -n /usr/local/lib/ntfs-autorw.sh
