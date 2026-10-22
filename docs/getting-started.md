# Getting started

This guide takes you from nothing to Linux Mint's desktop, in a virtual machine on your Mac or on a Raspberry Pi. Both start from the same image; the ready-made virtual machine is that image, already prepared for UTM.

## 1. Requirements

**In a virtual machine on a Mac:**

| What | Why | Check |
| --- | --- | --- |
| **A Mac with Apple silicon** (M1 or newer) | the system is built for ARM64 and runs on Apple's hypervisor at native speed | Apple menu › About This Mac: *Chip* |
| **[UTM](https://mac.getutm.app) 4.7 or newer** | runs the virtual machine; free from its website (or paid from the Mac App Store) | UTM › About UTM |
| **8 GB of memory to spare** | the ready-made VM is set to 8 GB; 4 GB is enough for light use | Activity Monitor › Memory |
| **5 GB of free disk space** | 2 GB to download; the VM then grows as you use it, up to 64 GB | Apple menu › About This Mac › More Info › Storage |

The ready-made VM was made and tested with UTM 4.7.5 on an M4 Max. It runs on any Mac with Apple silicon: Linux runs on the Mac's own cores, so a smaller Mac is slower in proportion, nothing more.

**On a Raspberry Pi:**

| What | Why |
| --- | --- |
| **A Raspberry Pi 4, 400 or Compute Module 4, or a Raspberry Pi 5, 500 or Compute Module 5** | one image works on all of them; older models are too slow for the desktop and are not supported |
| **4 GB of memory or more** | the desktop with Firefox runs in 2 GB, but slowly |
| **A microSD card of 16 GB or more**, or a USB or NVMe drive | the image needs 7 GB; at its first start the system grows to fill the card. A card rated A1 or A2 is noticeably faster |
| **[Raspberry Pi Imager](https://www.raspberrypi.com/software/)** | writes the image to the card, on a Mac, a PC or a Linux computer |
| **A screen, keyboard and mouse** | for the first-start setup and the desktop |
| **The Pi's own power supply** | the official 15 W supply for a Pi 4, the 27 W one for a Pi 5 (a weaker supply makes a Pi 5 limit its USB ports, and it says so) |
| **A network** | Ethernet, or Wi-Fi once the desktop is up; for updates and for translations other than English |

## 2. The ready-made virtual machine

This is the quickest way: Linux Mint is already installed, and its first start asks only for your preferences.

1. **Download** `linuxmint-22.3-cinnamon-arm64-unofficial-utm.zip` (1.8 GB) from the [latest release](https://github.com/GodisGood-GodisGreat-and-GodisReal-Amen/Mint-ARM/releases/latest). Take `SHA256SUMS` from the same page if you want to check the download.
2. **Check it** (optional). In Terminal, in the folder you downloaded to:

   ```bash
   shasum -a 256 -c SHA256SUMS --ignore-missing
   ```

   Each file you downloaded is listed with `OK`.
3. **Unzip it.** Double-click the zip: Finder unpacks **Linux Mint 22.3 ARM.utm**. Put it where you want to keep it (it grows as you use the system), and delete the zip.
4. **Open it.** Double-click **Linux Mint 22.3 ARM.utm**. UTM opens with *Linux Mint 22.3 ARM* in its list.
5. **Adjust it** (optional). Before the first start you can change the VM's size: select it, click the settings button in the toolbar, then *System* for the CPU cores (6 by default) and memory (8 GB), and *Display* for the display card (see the [manual](manual.md#3-the-display)). The disk holds up to 64 GB but only takes the space actually used.
6. **Start it.** Press **▶**. Linux Mint's setup starts:
   1. *Welcome*: the language of the system.
   2. *Keyboard layout*.
   3. *Where are you?*: the time zone.
   4. *Who are you?*: your name, the computer's name, your username and password, and whether to log in automatically.

   The setup then configures the system for a minute, removes its temporary setup account, and continues to the login screen, or straight to the desktop if you chose to log in automatically. From then on the VM starts like any computer.

If you chose a language other than English, the setup downloads its translations when the VM is online; otherwise add them later in *Language Settings*.

## 3. The image in a virtual machine of your own

The image also works as the disk of a VM you set up yourself: in UTM with Apple's Virtualization framework (for Rosetta, see the [manual](manual.md#8-rosetta-for-x86-64-programs)), or in another VM app that starts ARM64 UEFI systems.

1. **Download** `linuxmint-22.3-cinnamon-arm64-unofficial.img.xz` (1.46 GB) from the [latest release](https://github.com/GodisGood-GodisGreat-and-GodisReal-Amen/Mint-ARM/releases/latest), check it as above if you like, and **decompress** it: double-click it in Finder. That gives `linuxmint-22.3-cinnamon-arm64-unofficial.img` (7.12 GB).
2. **Create a VM** in UTM: **+** › **Virtualize** › **Linux**.
   - Turn on *Use Apple Virtualization* for Rosetta; leave it off for the GPU-accelerated display.
   - Skip the boot ISO image.
   - Memory: 4 to 8 GB. CPU cores: 4 to 6 is plenty.
   - **Save**.
3. **Give it the image as its disk.** In the VM's settings, remove the empty drive UTM made, add a drive with **Import…** and choose the `.img`, then **Resize** it to the size you want (64 GB, say). The system grows to fill it at its first start.
4. **Start it.** The first start removes the Raspberry Pi's half of the image, then Linux Mint's setup runs, as in the ready-made VM.

**Other VM apps.** The image is a standard ARM64 UEFI disk; VMware Fusion and Parallels Desktop run ARM64 Linux but have not been tested with it. Plain QEMU works: [`tools/testvm.sh`](../tools/testvm.sh) shows a complete command line.

## 4. On a Raspberry Pi

On a Pi, the same image goes on a card: Linux Mint is already installed, and its first start asks for your preferences. This release has not been tested on a real Raspberry Pi yet, only with the Pi's kernel in QEMU on a Mac.

1. **Download** `linuxmint-22.3-cinnamon-arm64-unofficial.img.xz` (1.46 GB) from the [latest release](https://github.com/GodisGood-GodisGreat-and-GodisReal-Amen/Mint-ARM/releases/latest), and check it as above if you like. Leave it compressed: Raspberry Pi Imager unpacks it while it writes.
2. **Write it to the card** with Raspberry Pi Imager:
   1. *Choose device*: your Raspberry Pi model.
   2. *Choose OS*: scroll to the end of the list, choose **Use custom**, and pick the `.img.xz` you downloaded.
   3. *Choose storage*: the microSD card (or USB drive). Everything on it is erased.
   4. **Next**. If Imager offers to apply *OS customisation* settings, choose **No**: Linux Mint's own setup asks for these at the first start. Writing and verifying takes a few minutes.
3. **Connect the Pi.** Put the card in, and connect the screen (on a Pi 4, preferably to the HDMI port next to the power socket, HDMI0), the keyboard, the mouse and, if you have one, an Ethernet cable. Connect the power last: the Pi starts by itself.
4. **The first start** takes a little longer than the next ones: the system grows to fill the card, and removes what only virtual machines use. Then Linux Mint's setup starts, as in the VM: *Welcome* (the language), *Keyboard layout*, *Where are you?* and *Who are you?*. It finishes as in the VM, at the login screen or, if you chose automatic login, on the desktop.
5. **Wi-Fi and Bluetooth** are in the panel's network and Bluetooth menus, as on any Linux Mint.

The [manual's Raspberry Pi section](manual.md#14-raspberry-pi) covers the boot partition and its settings, kernel and bootloader updates, starting from USB or NVMe, and what differs from the VM.

## 5. First steps

- **Install the updates.** Update Manager's shield in the panel shows what Ubuntu and Mozilla have published since the build. Install them as on any Linux Mint.
- **Add applications.** The Software Manager has LibreOffice, Thunderbird, GIMP and thousands more, built for ARM64. A few applications exist for x86 only; see the [manual](manual.md#7-installing-software).
- **Share files and the clipboard with the Mac** (in a VM). Clipboard sharing works out of the box; shared folders take one setting in UTM ([manual](manual.md#4-sharing-with-the-mac)).
- **Set up snapshots.** The *Welcome* screen's *First Steps* include Timeshift system snapshots. A copy of the stopped VM's `.utm` is a complete backup too; on a Pi, so is a copy of the card.

## 6. Updating

Ubuntu's updates and Firefox arrive through Update Manager, as on any Linux Mint system. Linux Mint's own packages (Cinnamon, Nemo, the Mint tools) stay at the versions built for this release, because Linux Mint publishes no ARM64 packages; a newer release of this project brings newer ones. The [manual](manual.md#6-updates) explains how the pieces fit.

## Next

The [user manual](manual.md) covers everything that differs from Linux Mint on a PC. [Troubleshooting](troubleshooting.md) helps when something does not work. To build the image and the VM yourself, see [Building it yourself](building.md).
