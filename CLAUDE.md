# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A from-scratch setup tool for running Debian KVM guest VMs on a Debian host **without libvirt** — every guest is launched as a single `qemu-system-x86_64` command line. The Makefile builds all the pieces (host kernel-bound guest kernel, busybox initrd, QEMU from source, debootstrapped template root image) and installs them under `/kvm/`. The `files/kvm` script is the runtime CLI that creates/connects/shuts down VMs.

## Branch layout

One branch per Debian release: `master`, `buster`, `bullseye`, `bookworm`. Switch branches to target a different guest distro — the `DEBIAN=` variable in the Makefile and the per-release package list in the `template:` target differ between branches. `master` typically tracks the newest stable; do **not** merge bookworm-specific package lists back to older branches.

## Common commands

All targets must run as root (they install into `/kvm/`, mount loop devices, and configure host networking).

```bash
sudo make all              # full setup: prep → initrd → kernel → qemu → files → template → template-modify
sudo make kernel           # build & install guest kernel (opens menuconfig the first time)
sudo make initrd           # build busybox-based initrd (boot/initrd-kvm.img)
sudo make qemu             # download & compile QEMU from source into /kvm/qemu/
sudo make busybox          # build busybox (opens menuconfig)
sudo make template         # debootstrap a fresh template.<release>64 root image
sudo make template-modify  # patch template: timezone, authorized_keys, /etc/hosts, sysv-init
sudo make files            # install /kvm/sbin/kvm, qemu-ifup, kbr0 bridge, ip_forward sysctl
sudo make hosts            # append v001..v250 entries to /etc/hosts (backs up first)
```

Per-VM operations (after install, all as root):

```bash
/kvm/sbin/kvm create v001            # boot VM v001 (copies template.img → v001.img if missing)
/kvm/sbin/kvm con v001               # attach to console UNIX socket (escape: Ctrl+])
/kvm/sbin/kvm mon v001               # attach to QEMU monitor socket
/kvm/sbin/kvm shutdown v001          # send system_powerdown via monitor
/kvm/sbin/kvm list                   # show id / con / mon / img status for all VMs
mem=4g smp=4 /kvm/sbin/kvm create v001  # override defaults (mem=1G, smp=2)
```

VM ids must match `v[0-9][0-9][0-9]`.

## Architecture

### Build pipeline (Makefile)

The Makefile is a thin orchestrator over four independent build artifacts that all land in `/kvm/`:

1. **Guest kernel** — wget kernel tarball → seed `.config` from `files/dot.config.kernel` → `menuconfig` (interactive) → build → install vmlinuz to `/kvm/boot/` and tar modules into `/kvm/boot/modules.tgz`. The `KVER_MINOR` (`-64kvmg01`) is patched into `CONFIG_LOCALVERSION` so the resulting vmlinuz/modules pair has a unique name. A neutered `~/bin/installkernel` is generated to skip distro postinst hooks.
2. **Busybox initrd** — `files/init` (ash script) is the entrypoint. It mounts `/dev/vda` as the rootfs, then mounts the host's `/kvm/boot` over **9p/virtio** as `kvmboot`, untars `modules.tgz` into the rootfs, then `switch_root`s into `/sbin/init`. This is why every VM shares one kernel+modules tree on the host — there are no per-VM modules.
3. **QEMU** — built from source into `/kvm/qemu/<version>/` and symlinked as `/kvm/qemu/qemu`. Configure flags enable kvm, spice, vhost-net, virtfs, linux-io-uring, linux-aio.
4. **Template root image** — `dd` a ~30 GB sparse file → `mkfs.ext4` → loop-mount → `debootstrap` Debian release with a curated package list (sysvinit-core, openssh-server, etc.) → set `root:root` password → unmount. `template-modify` then re-mounts to inject Asia/Tokyo timezone, `~/.ssh/authorized_keys`, `/etc/hosts`, `files/inittab`, and run `aptitude upgrade`. `template.img` symlinks the active template; new VMs are `cp template.img v???.img`.

### Runtime (`files/kvm`)

The `kvm` shell script generates the QEMU command line per VM:

- MAC addresses derived from the numeric id: `52:54:00:11:<id_hi>:<id_lo>` and `...:12:...`.
- A symlink `/kvm-$id` → qemu binary is created so the process shows up in `ps` as `kvm-v001` (then removed after `-daemonize` returns).
- Console + monitor sockets are UNIX sockets under `/kvm/console/` and `/kvm/monitor/`. `kvm con/mon` use `socat` with `Ctrl+]` rebinding for the escape sequence.
- `kvm list` discovers running VMs by grepping `/proc/net/unix` for the socket paths and `/proc/*/fd/*` for the disk image — there is no separate state file.
- The 9p `kvmboot` mount tag in the QEMU command line must match what `files/init` mounts.

### Host networking

`make files` installs:
- `/etc/network/interfaces.d/kbr0` — bridge `kbr0` at **10.0.0.254/24** with no physical ports attached (VMs only).
- `/etc/network/masquerade.sh` — `iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE` (run from kbr0's `up`).
- `/etc/sysctl.d/00-forward.conf` — enables `net.ipv4.ip_forward`.
- `/kvm/etc/qemu-ifup` — adds the VM's tap device to `kbr0`.

Each VM gets static IP `10.0.0.<IDNUM>` (passed to the guest via the kernel cmdline `IDNUM=`, consumed by `files/init` to write `/etc/network/interfaces`). Note: the README still documents `172.16.1.x` from an earlier version — the actual subnet in the current code is `10.0.0.0/24`.

## Editing notes

- `files/dot.config.kernel` and `files/dot.config.busybox` are committed snapshots of the menuconfig output. The Makefile copies them back over the source `.config` after a successful menuconfig run, so editing kernel/busybox config means: run `make kernel` (or `busybox`), do menuconfig, exit save, and commit the resulting diff in `files/dot.config.*`.
- The Makefile freely uses `aptitude install` (not `apt install`) — `aptitude` is in the host prerequisites listed in the README.
- Guest init system is **sysv-init** (`sysvinit-core` is in the debootstrap package list and `files/inittab` is copied in). Don't assume systemd inside guests.
- The whole setup assumes it can write to `/kvm/` and modify host networking — there is no install prefix override.
