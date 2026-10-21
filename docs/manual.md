# Linux Mint ARM user manual

Everything that differs from Linux Mint on a PC, in the order you meet it. For Linux Mint itself (the desktop, the applications, the tools), Linux Mint's own [documentation](https://linuxmint.com/documentation.php) applies unchanged; the *Welcome* screen links to it too.

## Contents

1. [The boot menu and the live session](#1-the-boot-menu-and-the-live-session)
2. [Installing](#2-installing)
3. [The first start of the ready-made VM](#3-the-first-start-of-the-ready-made-vm)
4. [The display](#4-the-display)
5. [Sharing with the Mac](#5-sharing-with-the-mac)
6. [Keyboard and mouse](#6-keyboard-and-mouse)
7. [Updates](#7-updates)
8. [Installing software](#8-installing-software)
9. [Rosetta for x86-64 programs](#9-rosetta-for-x86-64-programs)
10. [Memory and swap](#10-memory-and-swap)
11. [Disk space](#11-disk-space)
12. [The virtual machine's settings](#12-the-virtual-machines-settings)
13. [What was left out](#13-what-was-left-out)
14. [What this build adds to Linux Mint](#14-what-this-build-adds-to-linux-mint)

## 1. The boot menu and the live session

The ISO starts with a GRUB menu, chosen automatically after 10 seconds:

- **Start Linux Mint 22.3 Cinnamon ARM64**: the live session.
- **Start Linux Mint 22.3 Cinnamon ARM64 (compatibility mode)**: the same without the graphical boot splash and with the kernel's basic display driver. Use it when the screen stays black.
- **OEM install (for manufacturers)**: installs a system whose first start asks the next user for their language and account, which is how the ready-made VM was made.
- **Boot from next volume** and **UEFI Firmware Settings**.

![The live session](images/live-desktop.png)

The live session runs entirely in memory: nothing is written to the VM's disk until you install. It logs in as `mint` with no password. Applications installed in the live session vanish at shutdown. The medium is checked against its checksums in the background at start, as on Linux Mint's ISO.

## 2. Installing

**Install Linux Mint** on the live desktop starts Linux Mint's installer (Ubiquity), the same as on a PC: language, keyboard layout, multimedia codecs, installation type, time zone, your account. On a VM, *Erase disk and install Linux Mint* erases only the VM's own virtual disk. The installer creates a UEFI system partition, the root partition and a 2 GB swap file, and installs GRUB to the disk's standard removable path, so the system boots in any VM app without an entry in the firmware.

Installing takes about five minutes. The installer removes what only the live session needs (itself included) and keeps the rest; no internet connection is needed, except to add translations for a language other than English.

## 3. The first start of the ready-made VM

![The first start](images/first-start.png)

The ready-made VM was installed in OEM mode: Linux Mint is installed, but nothing is personal yet. Its first start runs *System Configuration*: your language, keyboard layout, time zone, and your name, the computer's name, username and password. It then removes the temporary account it was installed with, and the system starts normally. Every copy of the VM gets its own machine ID and random seed at this point.

## 4. The display

UTM offers two display cards for a QEMU virtual machine, chosen in the VM's settings › *Display* › *Emulated Display Card*. The ready-made VM uses the first.

| | **virtio-gpu-gl-pci** (*GPU Supported*) | **virtio-gpu-pci** |
| --- | --- | --- |
| Drawn by | the Mac's GPU: Mesa's VirGL driver in Linux, virglrenderer and ANGLE on the Mac, onto Metal | the VM's CPU (Mesa's llvmpipe) |
| OpenGL for programs | 2.1, and OpenGL ES 3.0 | 4.5 |
| glmark2 at 1280×720 | **1,608** | 162 |
| The Mac's CPU while the desktop is idle | **4.9 %** of one core | 13.4 % of one core |

Measured on an M4 Max with UTM's own QEMU, virglrenderer and ANGLE, with a 1920×1080 desktop.

The GPU display is the better choice for the desktop and most applications: Cinnamon's effects, video playback and GTK 4 applications all run on it. Its limit is OpenGL 2.1: a program that needs a newer OpenGL (Blender, OBS Studio and some games, for example) refuses to start. For those:

- run just that program on the CPU: `LIBGL_ALWAYS_SOFTWARE=1 blender` (from a terminal, or in the launcher's command);
- or switch the VM to `virtio-gpu-pci` while you use them;
- or try UTM's *Apple Core OpenGL* renderer (UTM › Settings › Display › *Renderer Backend*), which UTM documents as offering OpenGL 4.1 to the guest. It has not been tested with this build.

**Firefox** draws pages with its own software renderer, set by this build's Firefox policy (`gfx.webrender.software`). Drawing through UTM's accelerated OpenGL, Firefox showed pages and tabs without any text. Software rendering is fast enough for normal browsing on an Apple-silicon Mac. To try GPU drawing anyway, set `gfx.webrender.software` to `false` in `about:config` and restart Firefox.

**Vulkan** is not installed. UTM can pass Vulkan through to Linux (Mesa's Venus driver): install `mesa-vulkan-drivers` and see [UTM's notes](https://docs.getutm.app/guest-support/linux/). Untested here.

![Firefox on the GPU display](images/gpu-display.png)

**Resolution.** The desktop follows the size of UTM's window (the *Auto Resolution* option of UTM's display, done in Linux by `spice-vdagent`). UTM's *Retina Mode* is off: Linux draws at the window's size in points and macOS scales it, which is UTM's recommendation. For larger text and controls, use Cinnamon's *Display* settings › *User interface scaling*; for sharper text on a Retina screen, turn UTM's *Retina Mode* on and choose *Double (Hi-DPI)* scaling there.

## 5. Sharing with the Mac

**Clipboard.** Copy in one, paste in the other (`spice-vdagent` in Linux, and UTM's *Sharing* › *Enable Clipboard Sharing*, which is on in the ready-made VM).

**A shared folder.** In UTM, choose the folder with the folder button in the VM's toolbar (or *Sharing* in its settings). The ready-made VM uses UTM's *SPICE WebDAV* mode: inside Linux, `spice-webdavd` serves the folder at `http://127.0.0.1:9843`. To open it in Nemo, press **Ctrl+L**, type `dav://127.0.0.1:9843`, press Enter, and bookmark it with **Ctrl+D**.

UTM's other mode, *VirtFS*, mounts the folder as a file system instead (the kernel's `9p` driver is installed). Choose *VirtFS* in UTM's *Sharing* settings, then follow [UTM's instructions](https://docs.getutm.app/guest-support/linux/#virtfs): one line in `/etc/fstab`. Under Apple's Virtualization framework the folder arrives as *VirtioFS*: `sudo mkdir -p /mnt/share && sudo mount -t virtiofs share /mnt/share`.

**USB devices.** Turn on *USB Sharing* in the VM's settings › *Input*, then connect a device from the USB button in the VM's toolbar.

## 6. Keyboard and mouse

Shortcuts inside Linux use **Ctrl** (Ctrl+C, Ctrl+V); the Mac's **⌘** key reaches Linux as the Super key, which opens Cinnamon's menu. UTM can swap ⌘ and Ctrl for you (UTM › Settings › Input › *Control, Option, and Command keys*), so that ⌘C copies in Linux too.

If the mouse or keyboard is captured by the VM, **Control+Option** releases it. Scrolling direction can be set in Cinnamon's *Mouse and Touchpad* settings, or for all VMs with UTM's *Invert scrolling* option.

## 7. Updates

**Update Manager** works as on any Linux Mint, and three kinds of updates arrive through it:

- **Ubuntu's base and security updates**, from Ubuntu's archive for ARM, `ports.ubuntu.com` (the `noble`, `noble-updates`, `noble-backports` and `noble-security` suites). This includes the kernel: Ubuntu 24.04's hardware-enablement kernel, the line Linux Mint 22.3 uses too (7.0 at the time of this release), in its *virtual* flavour, the same kernel without the firmware for physical hardware. Update Manager keeps it up to date; Linux Mint's own version did not recognise this kernel line on ARM, and offered a 64k-page kernel instead, which Apple silicon cannot start, so this build's version is patched.
- **Firefox**, from Mozilla's own apt repository (`packages.mozilla.org`, ARM64). Firefox's built-in updater is off, as on Linux Mint.
- **Linux Mint's own packages** (Cinnamon, Nemo, the X-Apps, the Mint tools) come from the *Linux Mint ARM* archive stored in the system itself (`/usr/share/mint-arm/repo`). Linux Mint publishes no ARM64 packages, so these stay at the versions built for this release. A newer release of this project carries a `mint-arm-repo` package: install it (double-click it, or `sudo apt install ./mint-arm-repo_*.deb`), then run Update Manager to get the newer Mint packages.

The archive has the same priority (700) as Linux Mint's own repository, so Ubuntu's packages never replace Linux Mint's versions, even when Ubuntu's are numbered higher. `base-files`, which makes the system Linux Mint, is one example; GNOME Calculator 41 and Zenity 3.44, which Mint keeps on GTK 3, are others. The line for Linux Mint's repository stays in the sources, as on any Linux Mint system; apt finds no ARM64 packages there and moves on.

**Software Sources** offers Ubuntu's ARM mirrors for the *Base* repository, thirteen of them in ten countries, `ports.ubuntu.com` included, with Linux Mint's speed test. The stock tool only knows Ubuntu's x86 mirrors, where switching would have broken updates; this build patches it (see [How it works](architecture.md#software-sources-for-arm)). Linux Mint's own mirrors, offered for the *Main* repository, carry no ARM64 packages either way, so which one is chosen does not matter, and Update Manager does not suggest switching.

![Software Sources](images/software-sources.png)

## 8. Installing software

The **Software Manager** offers:

- Ubuntu's ARM64 packages, nearly everything Ubuntu has: LibreOffice, GIMP, VLC, Inkscape, Rhythmbox, development tools and thousands more.
- Linux Mint's applications that are not preinstalled, from the local archive: Pix, Warpinator, Hypnotix, Transmission and Onboard.
- **Flatpak** applications from Flathub, many of them built for ARM64: Chromium, Visual Studio Code and the Flatpak builds of LibreOffice, for example.

A few applications exist only for x86 PCs, and Linux Mint's own builds of some of them are x86 too:

- **Thunderbird**: Ubuntu publishes it only as a snap, and Flathub's build is x86 only. Install Mozilla Team's package instead: Software Sources › *PPAs* › **Add**, type `ppa:mozillateam/ppa`, then install `thunderbird` from the Software Manager or with `sudo apt install thunderbird`.
- **Chromium**: Ubuntu's package is a snap too; install the Flatpak from the Software Manager.
- **Closed-source applications** are sometimes published for x86-64 Linux only (Spotify and Steam, for example, are on Flathub for x86-64 only). Check the maker's download page for an ARM64 (`aarch64`) version; web versions work in Firefox, and some x86-64 programs run through Rosetta (see the next section).

Ubuntu's snap-only packages (Firefox, Thunderbird, Chromium) are hidden, as Linux Mint hides snapd, so the Software Manager never offers a package that cannot install.

## 9. Rosetta for x86-64 programs

Apple's Rosetta can translate x86-64 Linux programs inside a virtual machine that runs under **Apple's Virtualization framework** (macOS 13 or newer). The ready-made VM uses UTM's QEMU backend, which has the GPU-accelerated display but no Rosetta; for Rosetta, create a second VM:

1. In UTM: **+** › **Virtualize** › **Linux**, turn on **Use Apple Virtualization** and **Enable Rosetta (x86_64 Emulation)**, and choose the ISO as the boot image.
2. Install Linux Mint from the ISO as usual ([Getting started](getting-started.md#3-installing-from-the-iso)).
3. Change the kernel. Rosetta, at least up to macOS 15.7, stops every program on Linux kernels 6.13 and later with *rosetta error: unhandled auxillary vector type 29*: those kernels hand programs a piece of information (`AT_HWCAP3`) that Rosetta does not know. The system's kernel (7.0) is one of them; Ubuntu 24.04's long-term kernel, 6.8, works. Install it (about 700 MB with the firmware it brings, which a VM does not use):

   ```bash
   sudo apt install linux-image-generic
   ```

   Restart, holding **Esc** while the VM starts, and in GRUB's menu choose *Advanced options*, then the 6.8 kernel. Running on it, remove the newer kernel, so that 6.8 starts by default:

   ```bash
   sudo apt purge linux-image-virtual-hwe-24.04 'linux-image-7.*' 'linux-modules-7.*'
   ```

4. From then on, at each start the `mint-arm-rosetta` service finds Rosetta's share, mounts it and registers it for x86-64 programs (`cat /proc/sys/fs/binfmt_misc/rosetta` shows it).

Statically linked x86-64 programs then run as they are. Programs that need x86-64 libraries need those libraries too: enable the architecture with `sudo dpkg --add-architecture amd64`, add Ubuntu's x86-64 archive (`archive.ubuntu.com`) restricted to `[arch=amd64]`, and install the program's `:amd64` libraries. That is a project of its own, and not every program works.

Under Apple's Virtualization framework there is no GPU-accelerated display (the desktop is drawn on the CPU), and shared folders arrive as VirtioFS (see [Sharing](#5-sharing-with-the-mac)). These steps were tested with this build on macOS 15.7.

## 10. Memory and swap

The system swaps to **compressed RAM** first (`zram`, sized at half the VM's memory, at most 8 GB, compressed with zstd), and to the 2 GB swap file on disk only when that is full. Compressed RAM is much faster than any disk swap and typically holds three times its size, so an 8 GB VM behaves like a bigger one. The kernel is set to use it readily (`vm.swappiness=100`) and to read it a page at a time (`vm.page-cluster=0`).

`swapon --show` and `zramctl` show both. The VM's memory is set in UTM's settings › *System*.

## 11. Disk space

The ready-made VM's disk holds up to 64 GB and takes only the space actually written: under 2 GB on the Mac at first, as it comes compressed. A fresh install from the ISO uses about 7 GB of its disk, 2 GB of which is the swap file.

To make the disk bigger: shut the VM down, open its settings › the drive › **Resize**, start it again, then grow the system's partition and file system into the new space:

```bash
sudo apt install cloud-guest-utils
sudo growpart /dev/vda 2
sudo resize2fs /dev/vda2
```

(GParted, which the live session has, does the same with a window: *Partition* › *Resize/Move* on `/dev/vda2`.)

## 12. The virtual machine's settings

The ready-made VM is configured as follows. Every setting can be changed in UTM while the VM is stopped.

| Setting | Value |
| --- | --- |
| Backend | QEMU, with Apple's Hypervisor framework (native speed) |
| CPU cores, memory | 6, 8 GB |
| Display | `virtio-gpu-gl-pci` (GPU Supported), resolution follows the window |
| Disk | VirtIO, 64 GB, grows as needed |
| Network | `virtio-net-pci`, *Shared Network* (the Mac's connection, NAT) |
| Sound | Intel HD Audio |
| Sharing | clipboard on, directory sharing by SPICE WebDAV |
| Other | UEFI boot, random-number generator device, USB 3.0 controller with an empty CD/DVD drive |

*Shared Network* gives the VM internet access through the Mac. *Bridged* puts it on your local network with an address of its own, for example to reach it over SSH from other computers. UTM's **Run without saving changes** (in the VM's context menu) starts the VM in a disposable mode where nothing written is kept, handy for experiments. A copy of the stopped VM's `.utm` package is a complete backup.

## 13. What was left out

To keep the system light for a VM, these parts of Linux Mint's ISO are not installed. The applications are each one click away in the Software Manager:

- **Applications**: LibreOffice, Thunderbird (see [above](#8-installing-software)), Rhythmbox, Hypnotix, Transmission, Warpinator, Pix, Drawing, Onboard.
- **Developer packages**: debug symbols, the C and C++ compilers (`build-essential`) and kernel headers, only needed to build drivers, which a VM does not use.
- **Translations**: seven language packs that Linux Mint's ISO preinstalls (German, Spanish, French, Italian, Dutch, Portuguese and Russian). The installer and the first-start setup download the one you choose.
- **Hardware support a Mac VM does not have**: Bluetooth, fingerprint readers, Wi-Fi and mobile-broadband modems, firmware updates, power-management daemons, x86 microcode, Intel and NVIDIA drivers, touchpad gestures, scanners and printer manufacturers' drivers. Printing to network printers through CUPS works.

## 14. What this build adds to Linux Mint

Two packages carry everything this build changes (`apt show mint-arm-system mint-arm-repo` describes them).

`mint-arm-system`:

| File | Purpose |
| --- | --- |
| `/etc/apt/sources.list.d/mozilla.list`, `/etc/apt/keyrings/packages.mozilla.org.asc`, `/etc/apt/preferences.d/mozilla-firefox.pref` | Firefox from Mozilla's ARM64 apt repository, preferred over Ubuntu's |
| `/etc/apt/preferences.d/mint-arm-nosnap.pref` | hides Ubuntu's snap-only Firefox, Thunderbird and Chromium packages |
| `/etc/firefox/policies/policies.json` | Linux Mint's Firefox defaults, and software rendering ([display](#4-the-display)) |
| `/usr/lib/systemd/zram-generator.conf.d/50-mint-arm.conf`, `/usr/lib/sysctl.d/90-mint-arm-vm.conf` | compressed RAM swap and its memory settings |
| `/usr/lib/systemd/journald.conf.d/50-mint-arm.conf` | the system journal keeps at most 200 MB |
| `/usr/share/glib-2.0/schemas/90_mint-arm.gschema.override` | Update Manager does not suggest switching to a Linux Mint mirror |
| `/usr/lib/mint-arm/rosetta-setup`, `mint-arm-rosetta.service` | Rosetta, under Apple's Virtualization framework |
| `casper-md5check.service.d/mint-arm-live-only.conf` | the medium check runs in the live session only |

`mint-arm-repo`: the local *Linux Mint ARM* archive (`/usr/share/mint-arm/repo`), its signing key (`/usr/share/keyrings/mint-arm-archive.gpg`), its source line (`/etc/apt/sources.list.d/mint-arm.list`) and its priority (`/etc/apt/preferences.d/mint-arm.pref`).

Software Sources (`mintsources`) and Update Manager (`mintupdate`) are Linux Mint's, each with one patch: Software Sources offers Ubuntu's ARM mirrors, and Update Manager recognises the kernel line installed and never offers 64k-page kernels, which Apple silicon cannot start. The `firefox-locale-*` packages are small transition packages that install Mozilla's Firefox language packs. The rest is Linux Mint's and Ubuntu's software, unchanged.
