# Linux Mint ARM

Linux Mint 22.3 "Zena" with Cinnamon, rebuilt for ARM64. One image runs at native speed in a virtual machine on a Mac with Apple silicon, and on a Raspberry Pi 4 or 5: at its first start it sees which of the two it is on, and removes what the other needs. It comes ready to run in [UTM](https://mac.getutm.app), and as the image itself, for a Pi's card or a VM of your own. Both are made from the package list of the official x86 ISO, trimmed to be light: 4.67 GB installed in a VM instead of Linux Mint's 8.35 GB.

This is an **unofficial** build. The Linux Mint team did not make it, does not endorse it and does not support it.

![Linux Mint's welcome screen on the Cinnamon desktop, in a virtual machine on an M4 Mac](docs/images/welcome.png)

## What it does

- **The real Linux Mint, on ARM.** You get Cinnamon 6.6.9, Nemo and the X-Apps, plus Update Manager, Software Manager, Timeshift, Mint's first-start setup and Mint's themes and artwork. All 48 Linux Mint source packages that contain compiled code were rebuilt for ARM64 from Linux Mint's published sources. Mint's other packages are used as published.
- **One image, two kinds of machine.** The same image starts in a virtual machine (UEFI, GRUB, the hardware-enablement kernel) and on a Raspberry Pi (its firmware, Ubuntu's Raspberry Pi kernel). Its first start removes the half its machine does not use, then Linux Mint's setup asks for your language, keyboard, time zone and account.
- **Ready in three clicks.** Unzip the virtual machine, double-click it, press Play.
- **On a Raspberry Pi 4 or 5.** The Pi 4, 400 and CM4 and the Pi 5, 500 and CM5, written with Raspberry Pi Imager. It runs Ubuntu's Raspberry Pi kernel and desktop settings, with the Pi's own firmware for its GPU, Wi-Fi, Bluetooth and sound, and the system grows to fill the card at its first start. **Not yet tested on a real Pi**: this release was tested with the Pi's kernel in QEMU on a Mac ([what was tested](docs/architecture.md#tested-for-each-release)).
- **A GPU-accelerated desktop.** The Mac's GPU draws the desktop through Metal (UTM's *GPU Supported* display). glmark2 scores 1,608 instead of 162 on the CPU-drawn display, and the idle desktop costs the Mac 4.9 % of one core instead of 13.4 %.
- **Light.** About 1,580 packages in a VM instead of 2,005. A VM keeps no firmware or driver for hardware it doesn't have, and a Pi keeps only its own firmware. There is no live session or installer to carry. LibreOffice and the other large applications are one click away in the Software Manager.
- **Made for a virtual machine.** Swap is compressed in RAM. Clipboard sharing, automatic resizing, shared folders and the QEMU guest agent work out of the box, and VMware Fusion's tools are installed. Under Apple's Virtualization framework, Rosetta can run x86-64 Linux programs ([manual](docs/manual.md#8-rosetta-for-x86-64-programs)).
- **Updates keep working.** Update Manager brings Ubuntu's base and security updates from Ubuntu's ARM mirrors, and Software Sources is patched to offer them; Update Manager is patched too, so it keeps the right kernel, in the VM and on the Pi. Firefox is Mozilla's own ARM64 build, updated by Mozilla. Linux Mint's versions of its packages stay pinned, as on any Mint system.
- **Quick.** In a VM, the kernel and services are up in 1.5 seconds. The desktop runs in 0.9 GB of memory.
- **Rebuilt with one command.** `./build.sh` makes the image and the virtual machine from scratch on a Mac, in about 40 minutes on an M4 Max.

| First start | Firefox, native ARM64 | Software Sources, Ubuntu's ARM mirrors |
| --- | --- | --- |
| ![](docs/images/first-start.png) | ![](docs/images/firefox.png) | ![](docs/images/software-sources.png) |

## Quick start

You need a Mac with Apple silicon and [UTM](https://mac.getutm.app) 4.7 or newer (free).

1. Download `linuxmint-22.3-cinnamon-arm64-unofficial-utm.zip` from the [latest release](https://github.com/GodisGood-GodisGreat-and-GodisReal-Amen/Mint-ARM/releases/latest), and double-click it to unzip it.
2. Double-click **Linux Mint 22.3 ARM.utm**. UTM opens and adds it to its list.
3. Press **Play**. Linux Mint's setup asks for your language, keyboard, time zone and account, then starts the desktop.

**On a Raspberry Pi** 4 or 5, with [Raspberry Pi Imager](https://www.raspberrypi.com/software/):

1. Download `linuxmint-22.3-cinnamon-arm64-unofficial.img.xz` from the same release.
2. In Raspberry Pi Imager, choose your Pi, then **Use custom** at the end of the list of systems and the downloaded file, then your microSD card (16 GB or more). Write it.
3. Put the card in the Pi, connect the screen, keyboard and mouse, then the power. Linux Mint's setup starts once the system has grown to fill the card and removed what only virtual machines use.

The [startup guide](docs/getting-started.md) covers the image in a VM of your own, the Raspberry Pi in more detail, checking the downloads and the first things to do.

## Documentation

- [Getting started](docs/getting-started.md): requirements, the ready-made VM, the image in a VM of your own, the Raspberry Pi, first steps.
- [User manual](docs/manual.md): everything that differs from Linux Mint on a PC, including the display, sharing with the Mac, updates, software, memory, Rosetta, the VM's settings, and the Raspberry Pi.
- [Building it yourself](docs/building.md): the one-command build, its stages, changing what goes in, and the test tools.
- [How it works](docs/architecture.md): the package rebuild, the pinned local archive, the image and its two ways to start, the first start.
- [Troubleshooting](docs/troubleshooting.md): what to do when something does not work.
- [Contributing](CONTRIBUTING.md) and the [changelog](CHANGELOG.md).

## How it works, in one paragraph

Linux Mint 22.3 is Ubuntu 24.04 plus Linux Mint's own packages, and Linux Mint publishes those for x86 only. The build starts an Ubuntu 24.04 ARM64 virtual machine on the Mac. Inside it, Mint's 48 source packages that contain compiled code are rebuilt in four layers, each needing only earlier ones to build. Mint's architecture-independent packages are taken as they are. The original ISO's package list, trimmed, is then installed onto Ubuntu's ARM64 base from `ports.ubuntu.com`, with both machines' kernels and boot tools. A signed local "Linux Mint ARM" package archive inside the system holds Mint's packages at the priority Linux Mint gives its own repository, so Ubuntu's updates never replace them. The system goes into one disk image laid out like Ubuntu's Raspberry Pi images: its FAT boot partition holds the Pi's firmware and kernel and, beside them, GRUB for virtual machines. It is prepared the way Mint's installer prepares an OEM installation, so its first start removes what its machine does not use, then runs Mint's setup wizard. The ready-made UTM VM is that image on a 64 GB disk, its first start in a VM already done. [How it works](docs/architecture.md) has the details.

## Why a virtual machine on a Mac

No Linux distribution boots directly on an M4 Mac yet. [Asahi Linux](https://asahilinux.org) supports the M1 and M2, the M3 is in progress, and the M4 has neither an installer nor a GPU driver ([Asahi's M4 status](https://asahilinux.org/docs/platform/feature-support/m4/)). In a virtual machine on Apple's hypervisor, Linux Mint runs on the Mac's own cores at native speed. That works on any Mac with Apple silicon. The build was made and measured on an M4 Max.

## Privacy and network use

The system talks to the same servers as Linux Mint and adds nothing of its own: no telemetry, no account. Update Manager and apt fetch package lists and updates from Ubuntu's ARM mirrors and from Mozilla's apt repository. They also check Linux Mint's repository, which carries no ARM64 packages. Firefox goes wherever you browse.

On a Raspberry Pi, the bootloader update service compares the Pi's bootloader with the one in Ubuntu's package, on the Pi itself; it downloads nothing.

The build downloads from `cloud-images.ubuntu.com`, `ports.ubuntu.com`, `packages.linuxmint.com` and `packages.mozilla.org`, and nothing else. The published image and virtual machine were checked for traces of the machine that built them and carry none: no user or host names, keys, paths or network details. Each copy of the VM, and each card or disk written from the image, makes its own machine ID on its first start.

## License

The build scripts, the tools, the documentation, and what this project makes (`mint-arm-system`, `mint-arm-vm`, `mint-arm-pi`, `mint-arm-repo`, the `firefox-locale-*` transition packages, and the patches to Software Sources and Update Manager) are public domain. They are released under [The Unlicense](LICENSE): copy them, change them, sell them, build on them, no credit needed.

The image and the virtual machine contain software by Ubuntu, Linux Mint, Mozilla, Raspberry Pi Ltd and many others, each under its own license, mostly free-software licenses such as the GNU GPL. Each package's license is in `/usr/share/doc/<package>/copyright` inside the system. Every release also carries the source code of each Linux Mint package rebuilt for it, and a list of every source package in the images with where to get it.

Linux Mint's name and logo belong to the Linux Mint project. Ubuntu is a trademark of Canonical Ltd., Firefox of the Mozilla Foundation, Linux of Linus Torvalds, Raspberry Pi of Raspberry Pi Ltd, and Apple, Mac and Rosetta of Apple Inc. This project is not affiliated with any of them. The system keeps Linux Mint's name and artwork because it is Linux Mint's software, rebuilt. Please report problems with this build [here](https://github.com/GodisGood-GodisGreat-and-GodisReal-Amen/Mint-ARM/issues), not to the Linux Mint team.
