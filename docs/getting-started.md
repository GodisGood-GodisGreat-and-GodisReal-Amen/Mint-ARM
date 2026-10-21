# Getting started

This guide takes you from nothing to Linux Mint's desktop in a virtual machine on your Mac.

## 1. Requirements

| What | Why | Check |
| --- | --- | --- |
| **A Mac with Apple silicon** (M1 or newer) | the system is built for ARM64 and runs on Apple's hypervisor at native speed | Apple menu › About This Mac: *Chip* |
| **[UTM](https://mac.getutm.app) 4.7 or newer** | runs the virtual machine; free from its website (or paid from the Mac App Store) | UTM › About UTM |
| **8 GB of memory to spare** | the ready-made VM is set to 8 GB; 4 GB is enough for light use | Activity Monitor › Memory |
| **5 GB of free disk space** | 2 GB to download; the VM then grows as you use it, up to 64 GB | Apple menu › About This Mac › More Info › Storage |

The ready-made VM was made and tested with UTM 4.7.5 on an M4 Max. It runs on any Mac with Apple silicon: Linux runs on the Mac's own cores, so a smaller Mac is slower in proportion, nothing more.

## 2. The ready-made virtual machine

This is the quickest way: Linux Mint is already installed, and its first start asks only for your preferences.

1. **Download** `linuxmint-22.3-cinnamon-arm64-unofficial-utm.zip` (1.9 GB) from the [latest release](https://github.com/GodisGood-GodisGreat-and-GodisReal-Amen/Mint-ARM/releases/latest). Take `SHA256SUMS` from the same page if you want to check the download.
2. **Check it** (optional). In Terminal, in the folder you downloaded to:

   ```bash
   shasum -a 256 -c SHA256SUMS --ignore-missing
   ```

   Each file you downloaded is listed with `OK`.
3. **Unzip it.** Double-click the zip: Finder unpacks **Linux Mint 22.3 ARM.utm**. Put it where you want to keep it (it grows as you use the system), and delete the zip.
4. **Open it.** Double-click **Linux Mint 22.3 ARM.utm**. UTM opens with *Linux Mint 22.3 ARM* in its list.
5. **Adjust it** (optional). Before the first start you can change the VM's size: select it, click the settings button in the toolbar, then *System* for the CPU cores (6 by default) and memory (8 GB), and *Display* for the display card (see the [manual](manual.md#4-the-display)). The disk holds up to 64 GB but only takes the space actually used.
6. **Start it.** Press **▶**. Linux Mint's setup starts:
   1. *Welcome*: the language of the system.
   2. *Keyboard layout*.
   3. *Where are you?*: the time zone.
   4. *Who are you?*: your name, the computer's name, your username and password, and whether to log in automatically.

   The setup then configures the system for a minute, removes its temporary setup account, and continues to the login screen, or straight to the desktop if you chose to log in automatically. From then on the VM starts like any computer.

If you chose a language other than English, the setup downloads its translations when the VM is online; otherwise add them later in *Language Settings*.

## 3. Installing from the ISO

Use the ISO to install into a VM you configure yourself, for example with Apple's Virtualization framework for Rosetta (see the [manual](manual.md#9-rosetta-for-x86-64-programs)), or to try Linux Mint in a live session first.

1. **Download** `linuxmint-22.3-cinnamon-arm64-unofficial.iso` (1.65 GB) from the [latest release](https://github.com/GodisGood-GodisGreat-and-GodisReal-Amen/Mint-ARM/releases/latest), and check it as above if you like.
2. **Create a VM** in UTM: **+** › **Virtualize** › **Linux**.
   - Keep *Use Apple Virtualization* off unless you want Rosetta. The QEMU backend is the one with the GPU-accelerated display.
   - *Boot ISO Image*: **Browse…** and choose the ISO.
   - Memory: 4 to 8 GB. CPU cores: 4 to 6 is plenty.
   - Storage: 64 GB is a good size; only the space actually used is taken.
   - Shared directory: optional, and it can be chosen later.
   - **Save**.
3. **Choose the GPU display.** If the wizard offered hardware OpenGL acceleration and you turned it on, this is done. Otherwise open the VM's settings › *Display* and choose the *Emulated Display Card* marked *(GPU Supported)*, `virtio-gpu-gl-pci`. The [manual](manual.md#4-the-display) explains the choice.
4. **Start the VM.** A boot menu offers *Start Linux Mint 22.3 Cinnamon ARM64* (chosen after 10 seconds), a *compatibility mode* for display trouble, and an *OEM install* for preparing systems for someone else. The live desktop appears after about 10 seconds.
5. **Install.** Double-click **Install Linux Mint** on the live desktop and follow Linux Mint's installer: language, keyboard, multimedia codecs, *Erase disk and install Linux Mint* (this is the VM's own virtual disk), time zone, your account. It takes about five minutes.
6. **Restart without the ISO.** When the installer has finished, choose *Restart Now*. If the VM comes back to the installer's boot menu, or asks you to remove the installation medium, eject the ISO: click the drive button in UTM's toolbar, choose the CD/DVD drive, then *Eject*, and start the VM again.

**Other VM apps.** VMware Fusion and Parallels Desktop run ARM64 Linux, and the ISO is a standard ARM64 UEFI image, but neither has been tested. Plain QEMU works: [`tools/testvm.sh`](../tools/testvm.sh) shows a complete command line.

## 4. First steps

- **Install the updates.** Update Manager's shield in the panel shows what Ubuntu and Mozilla have published since the build. Install them as on any Linux Mint.
- **Add applications.** The Software Manager has LibreOffice, Thunderbird, GIMP and thousands more, built for ARM64. A few applications exist for x86 only; see the [manual](manual.md#8-installing-software).
- **Share files and the clipboard with the Mac.** Clipboard sharing works out of the box; shared folders take one setting in UTM ([manual](manual.md#5-sharing-with-the-mac)).
- **Set up snapshots.** The *Welcome* screen's *First Steps* include Timeshift system snapshots. A copy of the stopped VM's `.utm` is a complete backup too.

## 5. Updating

Ubuntu's updates and Firefox arrive through Update Manager, as on any Linux Mint system. Linux Mint's own packages (Cinnamon, Nemo, the Mint tools) stay at the versions built for this release, because Linux Mint publishes no ARM64 packages; a newer release of this project brings newer ones. The [manual](manual.md#7-updates) explains how the pieces fit.

## Next

The [user manual](manual.md) covers everything that differs from Linux Mint on a PC. [Troubleshooting](troubleshooting.md) helps when something does not work. To build the ISO and the VM yourself, see [Building it yourself](building.md).
