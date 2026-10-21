# Contributing

Thanks for looking under the hood. Linux Mint ARM is a set of shell scripts and a few small Python tools that turn Linux Mint's own packages into an ARM64 system. It has no dependencies beyond macOS, QEMU and the Ubuntu build VM it starts. Keep it that way where you can.

## Building from source

```bash
git clone https://github.com/GodisGood-GodisGreat-and-GodisReal-Amen/Mint-ARM.git
cd Mint-ARM
./build.sh
```

[Building it yourself](docs/building.md) covers the requirements, the stages, how to change what goes in, and testing. A first build takes about 35 minutes on an M4 Max; after a change, `./build.sh` again takes about 10, because the rebuilt Linux Mint packages are kept in `work/`.

## Layout

| File | What it is |
| --- | --- |
| `build.sh` | the one command: starts the build VM, runs the stages in it, makes the VM image |
| `build/00-build-vm.sh` | stage 00, on the Mac: the Ubuntu 24.04 ARM64 build VM (QEMU, Apple's hypervisor, cloud-init) |
| `build/10-packages.sh` | stage 10: rebuilds Linux Mint's compiled packages for ARM64; fetches its architecture-independent ones |
| `build/15-mintarm.sh` | stage 15: the patched Software Sources, `mint-arm-system`, the `firefox-locale-*` transition packages |
| `build/20-rootfs.sh` | stage 20: the system, the local archive (`mint-arm-repo`), the installer's media |
| `build/30-iso.sh` | stage 30: the ISO |
| `build/40-vm-image.sh` | stage 40, on the Mac: the unattended OEM install and the UTM package |
| `build/lib.sh` | helpers shared by the stages that run in the build VM |
| `build/packages.conf`, `build/roots.txt` | what goes into the system (see [building](docs/building.md#5-changing-what-goes-in)) |
| `build/select-packages.py`, `build/select-repo.py` | the package selection; what goes into the local archive |
| `build/mint-22.3-cinnamon-amd64.manifest`, `.manifest-remove` | Linux Mint's own package lists, from its x86 ISO |
| `build/mint-arm-system/` | the settings package, as files |
| `build/patches/` | changes to Linux Mint packages |
| `build/utm-oem.seed`, `build/utm-config.plist.in` | the OEM install's answers; the UTM VM's configuration |
| `tools/testvm.sh`, `tools/qmp.py`, `tools/qga.py` | headless test VMs: start, screenshots and input, commands and files |
| `tools/utm-qemu.sh`, `tools/utm-qemu.c` | the same on UTM's own QEMU, GPU-accelerated display included |
| `tools/vzvm.sh`, `tools/vzvm.swift`, `tools/x86-hello.py` | a test VM under Apple's Virtualization framework, with Rosetta, and a tiny x86-64 program to check it |
| `tools/plan.py` | what a Linux Mint release needs rebuilt, in which order, and `roots.txt` |
| `tools/make-release.sh`, `tools/source-manifest.py` | release files, with the source list and Linux Mint's sources |

[How it works](docs/architecture.md) explains each stage.

## Conventions

- **Scripts that run on the Mac are zsh; those in the build VM are bash.** Both use strict modes (`err_exit`/`pipe_fail`, `set -euo pipefail`). macOS ships zsh and its own BSD tools (`bsdtar`, `stat -f`, `shasum`); the build VM has GNU ones.
- **Every stage can run again.** Stage 10 builds only what is missing; the later stages start from nothing. Keep it that way: a build should never depend on what an earlier run left behind.
- **Linux Mint's packages are used as they are.** Change them only when ARM64 needs it, with a patch in `build/patches/` and a `+arm64.N` version suffix, and say why in the patch's comments.
- **Downloads are verified.** Keys are checked against their fingerprints, apt checks every package against its archive's signature, the cloud image against Ubuntu's checksums.
- **Comments say why, in plain words.** The scripts read like a description of the build on purpose; keep that voice.
- **Raise the version** of `mint-arm-system` in `build/mint-arm-system/DEBIAN/control` whenever one of its files changes; `mint-arm-repo` takes the same version.
- Match the existing style: two-space indent, long options where they explain themselves, one step per function.

## Debugging

- `./build.sh --keep-vm` leaves the build VM running; the log of every package build and apt run is in `/srv/mintarm/logs` inside it, and the system being assembled in `/srv/mintarm/rootfs`.
- `tools/testvm.sh` with `QGA_PORT` set gives a test VM with the guest agent: `tools/qga.py PORT run '...'` runs anything as root inside, `get` and `put` copy files.
- `tools/qmp.py PORT shot file.png` shows what the screen shows; `keys` and `click` drive it.
- On UTM's QEMU (`tools/utm-qemu.sh`), QEMU's screenshots are black while the display draws with OpenGL; take them inside the system (`gnome-screenshot -f /tmp/shot.png`, then `qga.py PORT get`).

## Pull requests

Keep them focused, describe what changed in the user's terms, and add a line to `CHANGELOG.md`. Say how you tested the change: which stages you ran, and what you checked in the result.

Linux Mint ARM is public domain under [The Unlicense](LICENSE). By contributing, you dedicate your contribution to the public domain on the same terms.
