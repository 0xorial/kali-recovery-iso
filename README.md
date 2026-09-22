# kali-recovery-iso

Kali live ISO (Xfce) for booting broken machines and working on them at
the keyboard or over SSH. It ships Kali's large toolset
(`kali-linux-large`), the full forensics category (`kali-tools-forensics`),
and extra filesystem, recovery and memory-forensics tools listed in
`extra-packages.list`. The default boot entry is amnesic; persistence is
optional (see below).

The ISO is built by GitHub Actions on native amd64 runners, weekly and on
demand, and each run's ISO is a 7-day download artifact. A local build path
for Apple Silicon Macs (Colima + Rosetta) also exists; see the end of this
file.

## Get the ISO and write it to a USB stick

The ISO is about 9GB, so use a stick of 16GB or more. Everything on the
stick is erased.

1. Download the latest successful build, from the repo's Actions tab or with
   `gh`:

   ```
   gh run list -R 0xorial/kali-recovery-iso -w build-iso -s success -L 1
   gh run download <run-id> -R 0xorial/kali-recovery-iso -n kali-recovery-iso -D kali-iso
   cd kali-iso && shasum -a 256 -c iso.sha256
   ```

2. Find the stick. Check the size and name carefully: writing to the wrong
   disk destroys it.

   ```
   diskutil list external
   ```

3. Write it, replacing `N` with the stick's disk number:

   ```
   diskutil unmountDisk /dev/diskN
   sudo dd if=kali-linux-rolling-live-xfce-amd64.iso of=/dev/rdiskN bs=4m status=progress
   ```

   When `dd` finishes, macOS reports the disk as unreadable. That's
   expected, because it can't read the Linux partitions. Click Eject.

## Boot menu

All four entries are stock Kali:

- "Live system": the default, fully amnesic. Nothing is written to the
  stick or the machine's disks.
- "Live system (forensic mode)": amnesic, and also never activates swap or
  auto-mounts the machine's disks. Use this on a machine whose disks you
  want untouched.
- "Live system with USB persistence" and "Live system with USB encrypted
  persistence": keep changes on a `persistence` partition on the stick (see
  below).

## SSH access

sshd starts at boot in every mode. Log in as `kali` with the key in
`authorized_keys` or with password `kali`.

- Reach it as `ssh kali@kali.local`. avahi (mDNS) is enabled, and macOS
  resolves `.local` names natively. If two sticks share a network, the
  second becomes `kali-2.local`.
- The IP is also shown on screen: a dialog pops up after desktop login once
  DHCP has an address, and the text consoles print `kali.local` and the
  IPv4 address above the login prompt.
- Host keys regenerate on every boot, so expect a known-hosts warning each
  time. To skip it:
  `ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null kali@kali.local`

Two things to know:

- The baked `authorized_keys` is the repo owner's public key. If you build
  from this repo, replace
  `kali-config-overlay/common/includes.chroot/etc/skel/.ssh/authorized_keys`
  with your own, or the owner's key can log into your stick.
- sshd with password `kali`, plus the avahi announcement, runs on whatever
  network the stick is plugged into, forensic mode included. On an
  untrusted network, run `passwd` after booting or keep the machine
  unplugged.

Password login works because of the drop-in
`/etc/ssh/sshd_config.d/10-recovery.conf`: Kali's live-config sets
`PasswordAuthentication no` in the main sshd_config at every live boot.

## Optional persistence

The persistence entries boot like the plain one until a partition labeled
`persistence` exists. To create it, boot the stick and run
`sudo make-persistence` (or `--encrypted` for a LUKS container); it uses the
stick's free space. The first two boot entries ignore the partition either
way.

`make-persistence` has not been run on real hardware yet.

## Known gaps

- No AVML: Kali doesn't package it. LiME is included for Linux memory
  capture.
- volatility3 isn't in Kali's amd64 archive, so it's installed from PyPI at
  build time, unpinned: each build gets the latest release.
- Artifacts expire after 7 days. Download the ISO you want to keep.

## Layout

- `.github/workflows/build-iso.yml`: the CI build and its checks.
- `extra-packages.list`: packages added on top of Kali's Xfce list. It's
  appended to upstream's current list at build time, so upstream changes
  still flow in.
- `kali-config-overlay/`: copied onto upstream's `kali-config/`.
  - `common/hooks/live/0900-enable-ssh.chroot`: enables sshd.
  - `common/hooks/live/0910-volatility3.chroot`: installs volatility3 from
    PyPI.
  - `common/hooks/live/0920-enable-mdns.chroot`: enables avahi.
  - `common/includes.chroot/etc/ssh/sshd_config.d/10-recovery.conf`:
    re-allows password login.
  - `common/includes.chroot/etc/skel/.ssh/authorized_keys`: the SSH
    public key.
  - `common/includes.chroot/usr/local/sbin/make-persistence`: creates the
    persistence partition.
  - `common/includes.chroot/usr/local/bin/show-ip` and
    `etc/xdg/autostart/show-ip.desktop`: the IP dialog.
  - `common/includes.chroot/etc/issue.d/ssh-address.issue`: the console
    banner.
- `setup-container.sh`, `container-overlay/`: the local Mac build (see
  the end of this file).

## CI build and verification

CI runs every Monday at 03:00 UTC and on demand
(`gh workflow run build-iso -R 0xorial/kali-recovery-iso`). The artifact
holds `kali-linux-rolling-live-xfce-amd64.iso` and `iso.sha256`.

Verification is static: the ISO is never booted during the build. CI mounts
the ISO, lists the live filesystem, and fails the run unless all of these
are present:

- zfs and LiME kernel modules under `lib/modules/*/updates/dkms/`
- volatility3 (`/usr/local/bin/vol`)
- zpool, zfs, cryptsetup, btrfs, testdisk, photorec, ddrescue, sshd
- sshd and avahi enabled at boot, plus the baked `authorized_keys`
- the IP dialog autostart and the console login banner

## Upkeep

- Each run clones the latest upstream `live-build-config`, so it picks up
  Kali's changes without anyone touching this repo. The cost is that an
  upstream change can break the build: on 2026-09-21 upstream rewrote
  `build.sh`, dropping `--verbose` and moving the ISO from `images/` to
  `output/`. A broken run fails with an error and uploads nothing.
- GitHub disables scheduled workflows after 60 days without repository
  activity. Any commit, or re-enabling the workflow in the Actions tab,
  restarts it.

## Local build on Apple Silicon (legacy)

`setup-container.sh` builds the same image in an amd64 container on a
Colima VM with Rosetta. It needs a Colima profile with about 80GB of disk:

```
colima start --profile kali --vm-type vz --vz-rosetta --cpu 8 --memory 8 --disk 80
./setup-container.sh
# then run the printed build command; ISO lands in /build/live-build-config/output/
```

This path hasn't been run since upstream's 2026-09-21 `build.sh` rewrite.
Only the CI path is known to work with the new script.

`kali-config/` is copied into `config/` when `build.sh` starts. Hooks or
package lists added while a build is running are ignored for that run.

To remove it all afterwards (`colima delete` alone leaves the VM's data
disk behind):

```
colima delete -p kali
LIMA_HOME=~/.colima/_lima limactl disk delete colima-kali
rm -f ~/.colima/_store/colima-kali.json
```

### Why the Rosetta patches exist

Rosetta refuses to run any amd64 binary inside a chroot unless `/proc` is
mounted there. It reads `/proc/self/exe`, and fails with ENOENT if that's
missing or ELOOP if `proc` is a self-referencing symlink. `container-overlay/`
holds the patched files at their container paths, written against
live-build `1:20250814+kali3` and debootstrap `1.0.144`. If those versions
change, re-check each patch instead of copying them over blindly.

- `usr/sbin/chroot`: wraps the real binary (diverted to `chroot.real` by
  `setup-container.sh`). It mounts `/proc` in the target for each call,
  unmounts it afterwards, and removes stale `proc` symlinks.
- `usr/share/debootstrap/scripts/debian-common`: drops the docker
  detection that symlinks `chroot/proc -> /proc` (the ELOOP case).
- `usr/lib/live/build/chroot_proc`: unmounts in a loop, because proc mounts
  stack.
- `usr/lib/live/build/chroot_cache`, `usr/lib/live/build/binary_chroot`:
  unmount `/proc` before each full-tree `cp -a`.
- `usr/lib/live/build/chroot`: the debug `ls -lR` at the end of the chroot
  stage always fails when it walks the mounted `/proc`, and `set -e` then
  kills the build. It's made non-fatal with `|| true`.
