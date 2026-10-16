# ntfs-autorw

**Plug in an NTFS drive on macOS → it appears writable at `/Volumes/<name>` — normal Finder sidebar, no notifications, no clicks, no password, no terminal.**

macOS mounts NTFS volumes **read-only** (its built-in FSKit driver). Commercial fix: Paragon NTFS (~$40). Popular free fix: [Mounty](https://mounty.app/) — but on recent macOS (FSKit-era, macOS 26/27+) Mounty's prompts can misfire and it mounts drives at a hidden `~/.mounty/<name>` folder instead of the normal `/Volumes` path.

**ntfs-autorw** is a 40-line launchd daemon that watches `/Volumes` (event-driven — it does *nothing* between mount events, no polling) and remounts any read-only NTFS volume read-write in place via **NTFS-3G + macFUSE**, as the logged-in console user.

## What you get

- Plug in any NTFS drive (or boot with one attached) → within a few seconds it's **writable at `/Volumes/<name>`**, with normal Finder sidebar presence
- No prompts, no password, no clicks
- Zero idle activity — the agent runs *only* when a volume actually mounts
- Works for every NTFS drive, forever, after a one-time setup

## Requirements (one-time)

```bash
brew install --cask macfuse
brew install gromgit/fuse/ntfs-3g-mac
```

Then approve macFUSE when macOS asks: **System Settings → Privacy & Security → Allow** ("Benjamin Fleischer"), and **restart** if asked. This approval is one-time and survives reboots.

## Install

```bash
git clone https://github.com/<owner>/ntfs-autorw.git
cd ntfs-autorw
sudo bash install.sh
```

Test: unplug and replug an NTFS drive. Within a few seconds:

```
$ mount | grep -i yourdrive
/dev/diskXs1 on /Volumes/yourdrive (macfuse, local, synchronous)
```

## Uninstall

```bash
sudo bash uninstall.sh
```

## macOS 26/27 note: use the user-agent variant

On recent macOS, a **system-domain LaunchDaemon** (root, boot-time) can be denied raw-device opens even as root — mounts fail with `Operation not permitted` / `Resource busy` while the identical command run from your session via `sudo` succeeds. If the daemon-installed path doesn't flip your drives, migrate to the **user-agent architecture**:

```bash
sudo bash migrate-user-agent.sh
```

This removes the system daemon and instead installs a **user LaunchAgent** (`com.ntfsautorw.watcher`, fires on `/Volumes` changes + at login) that calls the mount script through a **NOPASSWD sudoers entry scoped to exactly that one script**. The mount then runs in your session context — the configuration that demonstrably works. Verified on macOS 26/27, Apple Silicon.

## How it works

1. launchd `WatchPaths` on `/Volumes` fires **only when a volume mounts/unmounts**
2. The script waits briefly for FSKit to finish its read-only mount, then:
   - unmounts the read-only volume (and any Mounty-style `~/.mounty/<name>` mount)
   - remounts it at `/Volumes/<name>` via `ntfs-3g`, owned by the console user (`uid`/`gid` of `/dev/console`'s owner)
3. Volumes already mounted read-write are left alone

Activity is logged via `logger -t ntfs-autorw` (view: `log show --last 1h --predicate 'eventMessage CONTAINS "ntfs-autorw"'`).

## Manual fallback

Don't want any daemon? A standalone remount script is included:

```bash
sudo bash tools/mount-ntfs-rw.sh <VolumeName>
```

Run it after each plug-in/reboot. It also converts a Mounty `~/.mounty` mount back to `/Volumes`.

## Notes & troubleshooting

- **Drive still read-only after install** → macFUSE extension isn't approved: System Settings → Privacy & Security → Allow → restart → replug.
- **First-time mount takes a few seconds** — the agent waits for FSKit's read-only mount to appear before flipping it. This is normal.
- **Check what the agent actually did:**
  ```bash
  log show --last 30m --style compact | grep -E "ntfs-autorw"
  ```
  It logs every scan, candidate, success, and failure — including ntfs-3g's real error output.
- **A drive you want to stay read-only** — this remounts *every* NTFS volume. Comment out the `CANDS` collection in `ntfs-autorw.sh` to filter by name if needed.
- **Disclaimer**: always keep backups. You're using the open-source NTFS-3G driver to write to NTFS; treat it like any third-party filesystem driver.

### Debugging lessons (for anyone forking this)

Three failure classes we hit while building this, all of which fail **silently** if you're not careful:

1. **Mount-line parsing** — `mount` output uses `/dev/disk4s1` as the device field, while `diskutil`'s `DeviceIdentifier` is `disk4s1`. Match with the `/dev/` prefix or your "find the current mount" lookups silently return nothing.
2. **launchd root context** — a root LaunchDaemon has an **empty `TMPDIR`** and a minimal `PATH`. macFUSE helpers and ntfs-3g fail cryptically in that context. Export both explicitly.
3. **FSKit device claim + renumbering** — after force-unmounting an FSKit volume, the device holds an exclusive claim for a few seconds (`Operation not permitted` / `Resource busy` on open), and the device node can **vanish or renumber**. Re-resolve the device by volume name and retry the mount with a fresh node each attempt.

And the meta-lesson: **never pipe ntfs-3g's stderr to `/dev/null`**. Every failure above was invisible until we captured and logged the actual error output.

## Tested on

- Apple Silicon Mac, macOS 26/27 (FSKit-era read-only NTFS mounts), macFUSE 5.4, NTFS-3G 2026.9.28

## Alternatives compared

| | Paragon NTFS | Mounty | ntfs-autorw |
|---|---|---|---|
| Cost | ~$40 | free | free |
| Mount point | `/Volumes` (normal) | `~/.mounty/<name>` (hidden) on FSKit macOS | `/Volumes` (normal) |
| Automation | full | prompt per plug | fully automatic |
| Background footprint | several processes | resident app | runs only on mount events |

## License

MIT
