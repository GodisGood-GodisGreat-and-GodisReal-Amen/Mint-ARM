# Building it yourself

This guide rebuilds the image and the ready-made virtual machine from scratch, on a Mac, with one command. [How it works](architecture.md) explains what each stage does inside.

## 1. Requirements

| What | Why | Check |
| --- | --- | --- |
| **A Mac with Apple silicon** | the build runs in an ARM64 virtual machine on Apple's hypervisor | Apple menu › About This Mac: *Chip* |
| **QEMU from [Homebrew](https://brew.sh)** | runs the build VM, and the test VMs: `brew install qemu` | `qemu-system-aarch64 --version` |
| **16 GB of memory or more** | the build VM takes half the Mac's memory, between 6 and 32 GB | |
| **60 GB of free disk space** | the build VM's disk grows to about 40 GB; the results take 4 GB more | `df -h .` |
| **An internet connection** | about 5 GB of downloads: Ubuntu's cloud image and packages, Linux Mint's packages and sources, Firefox | |

Everything else the build uses is part of macOS: zsh, curl, ssh, bsdtar, hdiutil, plutil. The build was made on macOS 15 with QEMU 11.

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

About 45 minutes later on an M4 Max (with 8 of its cores), the results are in `out/`:

| File | What it is |
| --- | --- |
| `linuxmint-22.3-cinnamon-arm64-unofficial.img.xz` and its `.sha256` | the image: a Raspberry Pi's card, or a virtual machine's disk, prepared for its first-start setup |
| `Linux Mint 22.3 ARM.utm` | the ready-made UTM virtual machine: the image on a 64 GB disk, its first start in a VM already done |
| `linuxmint-22.3-cinnamon-arm64-unofficial.iso` and its `.sha256` | the live/install ISO for virtual machines, with Linux Mint's installer |
| `mint-arm-repo_<version>_all.deb` | the local archive of Linux Mint's packages, for updating systems made from an earlier release |

`work/` keeps the build VM's disk, about 40 GB. Running `./build.sh` again resumes: stage 10 only builds the packages still missing, and the later stages always start fresh, so a second run after a change takes about 25 minutes. Delete `work/` to free the space, or to start from nothing.

**Options.** `--test-ssh` also makes a test image that can be reached over SSH, for testing on a real Raspberry Pi ([section 7](#7-testing)); it is never for a release. `--keep-vm` leaves the build VM running at the end, for a look inside (`ssh -i work/build-vm/id_build -p 2299 builder@127.0.0.1`). A folder given as argument replaces `work/`, for example on another disk: `./build.sh /Volumes/Fast/mint-arm-work`. The settings in [section 8](#8-settings) adjust the rest.

**While it runs**, the Mac is busy: the build VM uses all performance cores unless told otherwise. `BUILD_CPUS=8 nice -n 10 ./build.sh` leaves room for other work. The Mac does not go to sleep until the build ends.

## 3. The stages

| Stage | Runs on | What it does | Time on an M4 Max |
| --- | --- | --- | --- |
| `00-build-vm.sh` | Mac | downloads Ubuntu 24.04's ARM64 cloud image (checking its SHA-256), starts it with QEMU on Apple's hypervisor, SSH on port 2299 | 15 s, plus the 600 MB download |
| `10-packages.sh` | build VM | rebuilds Linux Mint's 48 source packages with compiled code for ARM64, in four dependency layers; fetches Mint's 163 architecture-independent packages | 22 min |
| `15-mintarm.sh` | build VM | patches Software Sources (Ubuntu's ARM mirrors) and Update Manager (the kernel line); makes the settings packages (`mint-arm-system`, `mint-arm-vm`, `mint-arm-pi`) and the `firefox-locale-*` transition packages | 15 s |
| `20-rootfs.sh` | build VM | the system, with both machines' halves: debootstrap, Linux Mint's package selection, the local archive, the first-start setup; a copy for virtual machines with the live session and the installer, for the ISO; identical files stored once | 6 min |
| `30-image.sh` | build VM | the image: partitions, the system, the Raspberry Pi's boot files put on the boot partition by `flash-kernel` and GRUB installed beside them, checks, xz compression; the UTM VM's disk; with `--test-ssh`, the SSH test image | 15 min (19 with `--test-ssh`) |
| `35-iso.sh` | build VM | the live/install ISO: the live system as a squashfs, the installer's offline pool, the boot menu, shim and GRUB | 30 s |
| `40-vm-image.sh` | Mac | wraps the VM's disk as a UTM virtual machine | 5 s |

## 4. Running the stages by hand

`build.sh` only strings the stages together, and each one can be run on its own:

```bash
build/00-build-vm.sh work/build-vm &                         # the build VM, in the background
ssh -i work/build-vm/id_build -p 2299 builder@127.0.0.1      # once it has booted
```

Copy `build/` into the VM (`build.sh` does it with `tar` over SSH), then inside it run `bash build/10-packages.sh`, `15-mintarm.sh`, `20-rootfs.sh` and `30-image.sh` in turn. The image and the VM's disk land in `/srv/mintarm/out`; detailed logs of every package build, apt run and tool are in `/srv/mintarm/logs`. Back on the Mac, `build/40-vm-image.sh DISK.qcow2 OUT_DIR` makes the virtual machine.

## 5. Changing what goes in

Everything that decides the system's contents is in `build/`:

| File | What it decides |
| --- | --- |
| `packages.conf` | what is dropped from, kept from, and added to Linux Mint's own package list (`mint-22.3-cinnamon-amd64.manifest`, from the official ISO), and what the first start removes in a virtual machine (`[remove-on-vm]`) and on a Raspberry Pi (`[remove-on-pi]`). Lines are package names or shell-style patterns; every `[drop-…]` section drops. |
| `roots.txt` | the top-level packages kept as manually installed; everything else is marked automatic, so whatever only a dropped package needed is removed with it. Regenerate it after changing `packages.conf` (see [section 6](#6-a-newer-linux-mint)). |
| `mint-arm-system/`, `mint-arm-vm/`, `mint-arm-pi/` | the files this build adds to the system ([manual](manual.md#13-what-this-build-adds-to-linux-mint)): for every machine, for virtual machines, for the Raspberry Pi. Raise the version in `DEBIAN/control` whenever one changes (the three share it). |
| `pi/config.txt`, `pi/cmdline.txt` | the Raspberry Pi firmware's settings and the kernel's command line, on the image's boot partition. |
| `patches/` | changes to Linux Mint packages, applied by `15-mintarm.sh` (`build_patched`). |
| `utm-config.plist.in` | the UTM virtual machine's configuration. |

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

It prints the Linux Mint source packages that contain compiled code, in build layers (paste them into `LAYERS` in `build/10-packages.sh`), and writes `roots.txt`. For a new point release (22.4, say) that is most of the work; also update the release's name and number in `build/lib.sh` (`MINT_SUITE`), `30-image.sh`, `40-vm-image.sh`, `utm-config.plist.in` and the manifest file names, and check that `packages.conf` still matches. For a new major version, on a new Ubuntu base, expect more: the patch, the kernel package names and the Raspberry Pi packages may have moved.

## 7. Testing

`tools/` holds what the releases are tested with, all headless:

- `testvm.sh` runs a VM with the virtual hardware of UTM's QEMU backend, with no window. `qmp.py` takes screenshots and sends keys and clicks; `qga.py` runs commands and copies files through the QEMU guest agent, which the system includes in a VM.
- `utm-qemu.sh` runs a VM on UTM's own QEMU build instead, GPU-accelerated display included (virglrenderer and ANGLE onto Metal), to test exactly what UTM runs.
- `vzvm.sh` runs a VM under Apple's Virtualization framework, as UTM's *Use Apple Virtualization* option does, with Rosetta shared in. Its guest agent is reachable by `qga.py` too. Disks must be raw images.
- `testpi.sh` starts the image the way a Raspberry Pi does: the image's own Raspberry Pi kernel and initrd (copied off its boot partition by `pi-boot-files.py`) also run on QEMU's `virt` machine. With `APPEND=mint-arm.platform=pi`, the first start acts as on a Pi. Everything but the Pi's own hardware gets tested: the first start, the setup wizard, the desktop, the services, Update Manager, a kernel update through `flash-kernel`.
- `pitest.sh` talks to the SSH test image, on a real Pi or in a test VM: checks, screenshots, a shell, and taking the test access out again.

The image as a virtual machine's disk, through UEFI and GRUB, on an overlay that leaves the image untouched:

```bash
xz -dk out/linuxmint-22.3-cinnamon-arm64-unofficial.img.xz
qemu-img create -f qcow2 -b linuxmint-22.3-cinnamon-arm64-unofficial.img -F raw work/test.qcow2 32G
QGA_PORT=4460 tools/testvm.sh image work/test.qcow2 &
tools/qga.py 4460 ping                    # waits for the system to be up
tools/qmp.py 4450 shot setup.png          # the setup wizard, after the first start's clean-up
tools/qga.py 4460 run 'journalctl -u mint-arm-first-start -o cat'
tools/qmp.py 4450 cmd '{"name": "quit"}'
```

The same image as a Raspberry Pi starts it:

```bash
QMP_PORT=4461 APPEND=mint-arm.platform=pi tools/testpi.sh pi out/linuxmint-22.3-cinnamon-arm64-unofficial.img.xz &
tools/qmp.py 4461 shot pi.png
```

The ready-made VM without changing it (its first-start setup appears), and the same on UTM's QEMU, GPU display included (QEMU's own screenshots stay black there; take them inside the system with `gnome-screenshot`):

```bash
QGA_PORT=4460 tools/testvm.sh first-start "out/Linux Mint 22.3 ARM.utm/Data/"*.qcow2 -- -snapshot &
QGA_PORT=4460 tools/utm-qemu.sh gpu "out/Linux Mint 22.3 ARM.utm/Data/"*.qcow2 -- -snapshot &
tools/qga.py 4460 run 'grep -i glamor /var/log/Xorg.0.log'   # "glamor X acceleration enabled on virgl (ANGLE ... Metal ...)"
```

Under Apple's Virtualization framework, with Rosetta (the image, decompressed, as a raw disk):

```bash
tools/vzvm.sh rosetta --disk linuxmint-22.3-cinnamon-arm64-unofficial.img --qga-port 4460 &
tools/x86-hello.py work/hello && tools/qga.py 4460 put work/hello /tmp/hello
tools/qga.py 4460 run 'chmod +x /tmp/hello && /tmp/hello'      # "hello from x86-64, translated by Rosetta"
```

The ISO, in a test VM with an empty disk: its boot menu, the live session, then Linux Mint's installer:

```bash
qemu-img create -f qcow2 work/install.qcow2 64G
QGA_PORT=4460 tools/testvm.sh iso work/install.qcow2 out/linuxmint-22.3-cinnamon-arm64-unofficial.iso &
tools/qmp.py 4450 shot live.png
```

The one-command install, against the release files in `out/release/` (from `make-release.sh`) instead of GitHub, into a test folder and without opening UTM:

```bash
MINT_ARM_RELEASE=$(python3 -c 'import pathlib; print(pathlib.Path("out/release").resolve().as_uri())') \
  ./install.sh --dir work/vm --no-open
```

**On a real Raspberry Pi**, the Pi's own hardware gets tested: its firmware and `config.txt`, the GPU, Wi-Fi, Bluetooth, sound and the bootloader. `./build.sh --test-ssh` makes, next to the release image, a test image in `work/pi-test/`. It is the release image plus an SSH server: root logs in with a key made in `work/pi-test/` only (no passwords), and only from private network addresses; Avahi announces it on the network, from the setup wizard on; the Pi's bootloader is left as it is. Write it to a card with Raspberry Pi Imager, start the Pi on the same network as the Mac, then:

```bash
tools/pitest.sh find                       # "mint.local": the test image's host name
tools/pitest.sh mint.local check           # the system, the GPU, Wi-Fi, Bluetooth, sound, power, updates
tools/pitest.sh mint.local shot desktop.png
tools/pitest.sh mint.local remove          # takes the SSH access out again
```

The test image never goes to `out/`, and `make-release.sh` refuses an image with SSH access.

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
| `SQUASHFS_COMP` | `zstd` | the ISO's squashfs compression (`xz` for a smaller, slower ISO) |

Example: `BUILD_CPUS=8 UBUNTU_MIRROR=http://de.ports.ubuntu.com/ubuntu-ports ./build.sh`.

## 9. Making a release

```bash
./build.sh
tools/make-release.sh
```

`make-release.sh` puts the release files in `out/release/`: the image, the virtual machine as a zip, the ISO, the `mint-arm-repo` package, `SHA256SUMS`, and the source code that a release must carry. It also writes `imager/os_list.json` in the repository, Raspberry Pi Imager's entry for the new image (its download address, sizes and SHA-256s), with Raspberry Pi's current device list: commit it with the release, as Imager reads it from the repository. It starts the image headlessly in QEMU, on a throwaway overlay and with its first start held back (both halves still installed), lists the source package behind every binary package (`source-packages.tsv`, with where each source is published), and downloads Linux Mint's sources for every package compiled or patched for ARM64 into `linuxmint-22.3-arm64-sources.tar`, with apt checking them against Linux Mint's signed index. It refuses an image that has SSH access (a test image), and documents that still hold a `TODO-` placeholder for a measurement or the release date.

Before publishing: raise the version in `CHANGELOG.md` and, if they changed, in the settings packages' `DEBIAN/control`; test the image as a VM and as a Pi, the ready-made VM and the ISO (section 7); then create the release on GitHub with the files from `out/release/`, and push `imager/os_list.json` once the release exists. Each file must stay under GitHub's 2 GB limit; both scripts check it.
