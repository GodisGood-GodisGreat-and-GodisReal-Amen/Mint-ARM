# Contributing

Thanks for looking under the hood. Linux Mint ARM is a set of shell scripts and a few small Python tools that turn Linux Mint's own packages into an ARM64 system: one image that runs on a Raspberry Pi and in virtual machines. It has no dependencies beyond macOS, QEMU and the Ubuntu build VM it starts. Keep it that way where you can.

## Building from source

```bash
git clone https://github.com/GodisGood-GodisGreat-and-GodisReal-Amen/Mint-ARM.git
cd Mint-ARM
./build.sh
```

[Building it yourself](docs/building.md) covers the requirements, the stages, how to change what goes in, and testing. A first build takes about 45 minutes on an M4 Max; after a change, `./build.sh` again takes about 25 minutes, because the rebuilt Linux Mint packages are kept in `work/`.

## Layout

| File | What it is |
| --- | --- |
| `build.sh` | the one command: starts the build VM, runs the stages in it, copies the image and the ISO out, makes the UTM VM |
| `install.sh` | the one-command install of the ready-made VM on a Mac: UTM if missing, the download, its checksum, UTM |
| `build/00-build-vm.sh` | stage 00, on the Mac: the Ubuntu 24.04 ARM64 build VM (QEMU, Apple's hypervisor, cloud-init) |
| `build/10-packages.sh` | stage 10: rebuilds Linux Mint's compiled packages for ARM64; fetches its architecture-independent ones |
| `build/15-mintarm.sh` | stage 15: the patched Software Sources and Update Manager, the settings packages, the `firefox-locale-*` transition packages |
| `build/20-rootfs.sh` | stage 20: the system with both machines' halves, the local archive (`mint-arm-repo`), the first-start setup; the ISO's live system; identical files stored once |
| `build/30-image.sh` | stage 30: the image (for a Pi and for VMs), the UTM VM's disk, and the SSH test image |
| `build/35-iso.sh` | stage 35: the live/install ISO for virtual machines |
| `build/40-vm-image.sh` | stage 40, on the Mac: the UTM package |
| `build/lib.sh` | helpers shared by the stages that run in the build VM |
| `build/packages.conf`, `build/roots.txt` | what goes into the system, and what the first start removes on each machine (see [building](docs/building.md#5-changing-what-goes-in)) |
| `build/select-packages.py`, `build/select-repo.py` | the package selection; what goes into the local archive |
| `build/mint-22.3-cinnamon-amd64.manifest`, `.manifest-remove` | Linux Mint's own package lists, from its x86 ISO |
| `build/mint-arm-system/`, `build/mint-arm-vm/`, `build/mint-arm-pi/` | the settings packages, as files: every machine's (with the first-start service), the VMs', the Pi's |
| `build/pi/` | the Raspberry Pi's `config.txt` and `cmdline.txt` |
| `build/patches/` | changes to Linux Mint packages |
| `build/utm-config.plist.in` | the UTM VM's configuration |
| `tools/testvm.sh`, `tools/qmp.py`, `tools/qga.py` | headless test VMs: start, screenshots and input, commands and files |
| `tools/utm-qemu.sh`, `tools/utm-qemu.c` | the same on UTM's own QEMU, GPU-accelerated display included |
| `tools/vzvm.sh`, `tools/vzvm.swift`, `tools/x86-hello.py` | a test VM under Apple's Virtualization framework, with Rosetta, and a tiny x86-64 program to check it |
| `tools/testpi.sh`, `tools/pi-boot-files.py` | the image in QEMU on the Mac as a Raspberry Pi starts it, on its own Raspberry Pi kernel |
| `tools/pitest.sh` | checks, screenshots and a shell on the SSH test image, on a real Pi or in `testpi.sh` |
| `tools/plan.py` | what a Linux Mint release needs rebuilt, in which order, and `roots.txt` |
| `tools/make-release.sh`, `tools/source-manifest.py` | release files, with the source list and Linux Mint's sources, and Raspberry Pi Imager's list |
| `imager/os_list.json`, `imager/icon.png` | Raspberry Pi Imager's list with this project's image (written by `make-release.sh`), and its icon |

[How it works](docs/architecture.md) explains each stage.

## Conventions

- **Scripts that run on the Mac are zsh; those in the build VM are bash.** Both use strict modes (`err_exit`/`pipe_fail`, `set -euo pipefail`). macOS ships zsh and its own BSD tools (`bsdtar`, `stat -f`, `shasum`); the build VM has GNU ones.
- **Every stage can run again.** Stage 10 builds only what is missing; the later stages start from nothing. Keep it that way: a build should never depend on what an earlier run left behind.
- **Linux Mint's packages are used as they are.** Change them only when ARM64 needs it, with a patch in `build/patches/` and a `+arm64.N` version suffix, and say why in the patch's comments.
- **Downloads are verified.** Keys are checked against their fingerprints, apt checks every package against its archive's signature, the cloud image against Ubuntu's checksums.
- **Comments say why, in plain words.** The scripts read like a description of the build on purpose; keep that voice.
- **Raise the version** of the settings packages in their `DEBIAN/control` files whenever one of their files changes; the three share one version, and `mint-arm-repo` takes it too.
- Match the existing style: two-space indent, long options where they explain themselves, one step per function.

## Debugging

- `./build.sh --keep-vm` leaves the build VM running; the log of every package build and apt run is in `/srv/mintarm/logs` inside it, and the system being assembled in `/srv/mintarm/rootfs`.
- `tools/testpi.sh` starts the image on the Mac as a Pi would; the SSH test image (`./build.sh --test-ssh`) and `tools/pitest.sh` reach it, there or on a real Pi.
- `tools/testvm.sh` with `QGA_PORT` set gives a test VM with the guest agent: `tools/qga.py PORT run '...'` runs anything as root inside, `get` and `put` copy files.
- `tools/qmp.py PORT shot file.png` shows what the screen shows; `keys` and `click` drive it.
- On UTM's QEMU (`tools/utm-qemu.sh`), QEMU's screenshots are black while the display draws with OpenGL; take them inside the system (`gnome-screenshot -f /tmp/shot.png`, then `qga.py PORT get`).

## Pull requests

Keep them focused, describe what changed in the user's terms, and add a line to `CHANGELOG.md`. Say how you tested the change: which stages you ran, and what you checked in the result.

Linux Mint ARM is public domain under [The Unlicense](LICENSE). By contributing, you dedicate your contribution to the public domain on the same terms.
