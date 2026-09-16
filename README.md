# kali-recovery-iso

Custom Kali live ISO (xfce variant, non-persistent) with extra
filesystem/data-recovery tooling and sshd enabled — built for booting broken
machines and working on them locally or over SSH.

Built on an ARM Mac via Colima (`kali` profile, vz + Rosetta) in an amd64
`kalilinux/kali-rolling` container. That cross-arch setup is why this repo
exists: stock live-build breaks in several places under Rosetta emulation,
and the fixes live in `container-overlay/`.

## Layout

- `setup-container.sh` — recreates the builder container from scratch:
  volumes, deps, patches, repo clone, config overlay. Run it, then use the
  build command it prints.
- `container-overlay/` — patched build-tool files, mirrored at their
  container paths. Written against live-build `1:20250814+kali3` and
  debootstrap `1.0.144`; if those move, re-verify each patch instead of
  blindly overwriting.
- `kali-config-overlay/` — our image customizations, mirrored onto
  `live-build-config/kali-config/`:
  - `variant-xfce/package-lists/kali.list.chroot` — full package list
    (upstream's file + our additions at the bottom: ZFS, btrfs, LUKS, LVM,
    mdadm, testdisk, ddrescue, sleuthkit, etc. + openssh-server). Note this
    snapshots the upstream list too — diff against upstream when they drift.
  - `common/hooks/live/0900-enable-ssh.chroot` — enables sshd in the live
    image (login: kali/kali, host keys regenerate every boot).

## Why each patch (Rosetta on Apple Silicon)

Rosetta refuses to exec any amd64 binary inside a chroot unless `/proc` is
mounted there (it reads `/proc/self/exe`; ENOENT without it, ELOOP if
`proc` is a self-referential symlink).

- `usr/sbin/chroot` — wrapper around the diverted real binary
  (`chroot.real`): mounts `/proc` in the target for each call, unmounts
  after, removes stale `proc` symlinks. `setup-container.sh` performs the
  `dpkg-divert`.
- `usr/share/debootstrap/scripts/debian-common` — drop the docker
  detection that symlinks `chroot/proc -> /proc` (the ELOOP case).
- `usr/lib/live/build/chroot_proc` — unmount loop; proc mounts stack.
- `usr/lib/live/build/chroot_cache`, `usr/lib/live/build/binary_chroot` —
  failsafe unmount before each full-tree `cp -a`.
- `usr/lib/live/build/chroot` — the trailing debug `ls -lR` inside the
  chroot always exits non-zero when it walks the wrapper-mounted live
  `/proc`, and `set -e` kills the build; made non-fatal with `|| true`.

## Build + verify

```
./setup-container.sh
# then the printed build command; ISO lands in /build/live-build-config/images/
```

Verification (static, per spec — never boot the ISO from here): sha256 the
ISO, `unsquashfs` the live filesystem, confirm `zfs.ko*` exists under
`lib/modules/*/updates/dkms/` and that zpool/zfs/cryptsetup/btrfs/testdisk/
photorec/ddrescue binaries are present.

## SSH access (recovery workflow)

The image boots with sshd enabled. Log in as `kali` with the baked-in
public key (`includes.chroot/etc/skel/.ssh/authorized_keys`) or password
`kali` — password auth is re-allowed by the `sshd_config.d` drop-in,
because Kali's live-config component sets `PasswordAuthentication no` in
the main sshd_config at every live boot. Host keys regenerate each boot
(the image is amnesic), so expect the known-hosts warning.

Gotcha learned the hard way: `kali-config/` is snapshotted into `config/`
when `build.sh` starts. Hooks or lists added while a build is running are
silently ignored for that run.
