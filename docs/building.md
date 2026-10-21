# Building it yourself

This guide rebuilds the ISO and the ready-made virtual machine from scratch, on a Mac, with one command. [How it works](architecture.md) explains what each stage does inside.

## 1. Requirements

| What | Why | Check |
| --- | --- | --- |
| **A Mac with Apple silicon** | the build runs in an ARM64 virtual machine on Apple's hypervisor | Apple menu › About This Mac: *Chip* |
| **QEMU from [Homebrew](https://brew.sh)** | runs the build VM and the install VM: `brew install qemu` | `qemu-system-aarch64 --version` |
| **16 GB of memory or more** | the build VM takes half the Mac's memory, between 6 and 32 GB | |
| **50 GB of free disk space** | the build VM's disk grows to about 40 GB; the results take 4 GB more | `df -h .` |
| **An internet connection** | about 5 GB of downloads: Ubuntu's cloud image and packages, Linux Mint's packages and sources, Firefox | |

Everything else the build uses is part of macOS: zsh, curl, ssh, bsdtar, cpio, hdiutil, plutil. The build was made on macOS 15 with QEMU 11.

## 2. One command

```bash
git clone https://github.com/GodisGood-GodisGreat-and-GodisReal-Amen/Mint-ARM.git
cd Mint-ARM
./build.sh
```

It prints one line per step, and each stage's progress:

```
[18:01:03] starting the build VM
[18:01:16] copying build/ into the VM
[18:01:16] stage 10-packages
[18:01:49] fetched 163 Architecture: all packages from Mint
[18:01:52] layer 1: xapp cinnamon-desktop cinnamon-menus cjs ...
[18:04:18] OK   cinnamon-menus 6.6.0+zena
[18:04:19] OK   xapp 3.2.3+zena
...
```

About 35 minutes later on an M4 Max (with 8 of its cores), the results are in `out/`:

| File | What it is |
| --- | --- |
| `linuxmint-22.3-cinnamon-arm64-unofficial.iso` and its `.sha256` | the live system and installer |
| `Linux Mint 22.3 ARM.utm` | the ready-made UTM virtual machine, preinstalled in OEM mode |
| `mint-arm-repo_<version>_all.deb` | the local archive of Linux Mint's packages, for updating systems made from an earlier release |

`work/` keeps the build VM's disk, about 40 GB. Running `./build.sh` again resumes: stage 10 only builds the packages still missing, and the later stages always start fresh, so a second run after a change takes about 10 minutes. Delete `work/` to free the space, or to start from nothing.

**Options.** `./build.sh --keep-vm` leaves the build VM running at the end, for a look inside (`ssh -i work/build-vm/id_build -p 2299 builder@127.0.0.1`). A folder given as argument replaces `work/`, for example on another disk: `./build.sh /Volumes/Fast/mint-arm-work`. The settings in [section 8](#8-settings) adjust the rest.

**While it runs**, the Mac is busy: the build VM uses all performance cores unless told otherwise. `BUILD_CPUS=8 nice -n 10 ./build.sh` leaves room for other work. The Mac does not go to sleep until the build ends.

## 3. The stages

| Stage | Runs on | What it does | Time on an M4 Max |
| --- | --- | --- | --- |
| `00-build-vm.sh` | Mac | downloads Ubuntu 24.04's ARM64 cloud image (checking its SHA-256), starts it with QEMU on Apple's hypervisor, SSH on port 2299 | 15 s, plus the 600 MB download |
| `10-packages.sh` | build VM | rebuilds Linux Mint's 48 source packages with compiled code for ARM64, in four dependency layers; fetches Mint's 163 architecture-independent packages | 24 min |
| `15-mintarm.sh` | build VM | patches Software Sources (Ubuntu's ARM mirrors) and Update Manager (the kernel line); makes `mint-arm-system` and the `firefox-locale-*` transition packages | 15 s |
| `20-rootfs.sh` | build VM | the system: debootstrap, Linux Mint's package selection, the local archive, the installer's offline packages | 5 min |
| `30-iso.sh` | build VM | compresses the system (squashfs, zstd), adds the UEFI boot chain, writes the ISO | 30 s |
| `40-vm-image.sh` | Mac | Linux Mint's installer preinstalls the ISO in OEM mode, unattended; packs the UTM virtual machine | 2 min |

## 4. Running the stages by hand

`build.sh` only strings the stages together, and each one can be run on its own:

```bash
build/00-build-vm.sh work/build-vm &                         # the build VM, in the background
ssh -i work/build-vm/id_build -p 2299 builder@127.0.0.1      # once it has booted
```

Copy `build/` into the VM (`build.sh` does it with `tar` over SSH), then inside it run `bash build/10-packages.sh`, `15-mintarm.sh`, `20-rootfs.sh` and `30-iso.sh` in turn. The ISO lands in `/srv/mintarm/out`; detailed logs of every package build, apt run and tool are in `/srv/mintarm/logs`. Back on the Mac, `build/40-vm-image.sh ISO OUT_DIR` makes the virtual machine.

## 5. Changing what goes in

Everything that decides the system's contents is in `build/`:

| File | What it decides |
| --- | --- |
| `packages.conf` | what is dropped from, kept from, and added to Linux Mint's own package list (`mint-22.3-cinnamon-amd64.manifest`, from the official ISO). Lines are package names or shell-style patterns. |
| `roots.txt` | the top-level packages kept as manually installed; everything else is marked automatic, so whatever only a dropped package needed is removed with it. Regenerate it after changing `packages.conf` (see [section 6](#6-a-newer-linux-mint)). |
| `mint-arm-system/` | the files this build adds to the system ([manual](manual.md#14-what-this-build-adds-to-linux-mint)). Raise the version in `DEBIAN/control` whenever it changes. |
| `patches/` | changes to Linux Mint packages, applied by `15-mintarm.sh` (`build_patched`). |
| `utm-oem.seed`, `utm-config.plist.in` | the unattended OEM install of the VM, and the UTM VM's configuration. |

Then run `./build.sh` again: the rebuilt packages are kept, the system is assembled afresh.

For example, to preinstall LibreOffice Writer, add `libreoffice-writer` to `[add]` in `packages.conf`; to leave out Celluloid, add `celluloid` to `[drop-light]`.

## 6. A newer Linux Mint

The build follows one Linux Mint release: 22.3 "Zena", based on Ubuntu 24.04 "Noble". `tools/plan.py` works out what a different release needs from its official ISO:

```bash
bsdtar -xOf linuxmint-22.3-cinnamon-64bit.iso casper/filesystem.manifest > build/mint-22.3-cinnamon-amd64.manifest
bsdtar -xOf linuxmint-22.3-cinnamon-64bit.iso casper/filesystem.manifest-remove > build/mint-22.3-cinnamon-amd64.manifest-remove
tools/plan.py fetch work/index zena noble
tools/plan.py plan work/index build/mint-22.3-cinnamon-amd64.manifest build/packages.conf build/roots.txt
```

It prints the Linux Mint source packages that contain compiled code, in build layers (paste them into `LAYERS` in `build/10-packages.sh`), and writes `roots.txt`. For a new point release (22.4, say) that is most of the work; also update the release's name and number in `build/lib.sh` (`MINT_SUITE`), `30-iso.sh`, `40-vm-image.sh`, `utm-config.plist.in` and the manifest file names, and check that `packages.conf` still matches. For a new major version, on a new Ubuntu base, expect more: the patch, the kernel package names and the installer may have moved.

## 7. Testing

`tools/` holds what the releases are tested with, all headless:

- `testvm.sh` runs a VM with the virtual hardware of UTM's QEMU backend, with no window. `qmp.py` takes screenshots and sends keys and clicks; `qga.py` runs commands and copies files through the QEMU guest agent, which the system includes.
- `utm-qemu.sh` runs a VM on UTM's own QEMU build instead, GPU-accelerated display included (virglrenderer and ANGLE onto Metal), to test exactly what UTM runs.
- `vzvm.sh` runs a VM under Apple's Virtualization framework, as UTM's *Use Apple Virtualization* option does, with Rosetta shared in. Its guest agent is reachable by `qga.py` too. Disks must be raw images (`qemu-img convert -O raw`).

Boot the ISO with a fresh disk, then look at it and talk to it:

```bash
qemu-img create -f qcow2 work/test.qcow2 64G
QGA_PORT=4460 tools/testvm.sh live work/test.qcow2 out/linuxmint-22.3-cinnamon-arm64-unofficial.iso &
tools/qga.py 4460 ping                    # waits for the system to be up
tools/qmp.py 4450 shot live.png           # a screenshot
tools/qga.py 4460 run 'systemd-analyze; free -h'
tools/qmp.py 4450 cmd '{"name": "quit"}'
```

Start the ready-made VM without changing it (its first-start setup appears) with `-- -snapshot`:

```bash
QGA_PORT=4460 tools/testvm.sh first-start "out/Linux Mint 22.3 ARM.utm/Data/"*.qcow2 -- -snapshot &
```

The same on UTM's QEMU, GPU display included (QEMU's own screenshots stay black there; take them inside the system with `gnome-screenshot`):

```bash
QGA_PORT=4460 tools/utm-qemu.sh gpu "out/Linux Mint 22.3 ARM.utm/Data/"*.qcow2 -- -snapshot &
tools/qga.py 4460 run 'grep -i glamor /var/log/Xorg.0.log'   # "glamor X acceleration enabled on virgl (ANGLE ... Metal ...)"
```

The live ISO under Apple's Virtualization framework, with Rosetta:

```bash
tools/vzvm.sh rosetta --iso out/linuxmint-22.3-cinnamon-arm64-unofficial.iso --qga-port 4460 &
tools/qga.py 4460 ping
tools/x86-hello.py work/hello && tools/qga.py 4460 put work/hello /tmp/hello
tools/qga.py 4460 run 'chmod +x /tmp/hello && /tmp/hello'      # "hello from x86-64, translated by Rosetta"
```

## 8. Settings

`build.sh` passes these to the stages:

| Variable | Default | Meaning |
| --- | --- | --- |
| `BUILD_CPUS` | the Mac's performance cores | the build VM's CPU count |
| `BUILD_MEM` | half the Mac's memory, 6 to 32 GB | the build VM's memory, e.g. `16G` |
| `BUILD_SSH_PORT` | `2299` | the Mac's port forwarded to the build VM's SSH |
| `OUT` | `out/` | where the results go |
| `JOBS` | the build VM's CPU count | compiler jobs in stage 10, shared between the packages built at once |
| `PAR` | `3` | how many packages stage 10 builds at once |
| `MINT_MIRROR` | `http://packages.linuxmint.com` | where Linux Mint's packages and sources come from |
| `UBUNTU_MIRROR` | `http://ports.ubuntu.com/ubuntu-ports` | Ubuntu's ARM archive (any `ubuntu-ports` mirror) |
| `SQUASHFS_COMP` | `zstd` | the ISO's compression; `xz` is also understood (a somewhat smaller ISO, much slower to build) |

Example: `BUILD_CPUS=8 UBUNTU_MIRROR=http://de.ports.ubuntu.com/ubuntu-ports ./build.sh`.

## 9. Making a release

```bash
./build.sh
tools/make-release.sh
```

`make-release.sh` puts the release files in `out/release/`: the ISO, the virtual machine as a zip, the `mint-arm-repo` package, `SHA256SUMS`, and the source code that a release must carry. It boots the new ISO headlessly with the new VM's disk attached read-only, lists the source package behind every binary package in both (`source-packages.tsv`, with where each source is published), and downloads Linux Mint's sources for every package compiled or patched for ARM64 into `linuxmint-22.3-arm64-sources.tar`, with apt checking them against Linux Mint's signed index.

Before publishing: raise the version in `CHANGELOG.md` and, if it changed, in `build/mint-arm-system/DEBIAN/control`; test the ISO and the VM (section 7); then create the release on GitHub with the files from `out/release/`.
