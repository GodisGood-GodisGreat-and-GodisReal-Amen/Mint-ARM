# How Linux Mint ARM is made

A map of the build for anyone who wants to change it.

## The shape of it

```
the Mac (zsh)                                    build VM: Ubuntu 24.04 ARM64 (bash)
┌──────────────────────────────┐     ssh      ┌────────────────────────────────────────────┐
│ build.sh                     │ ───────────► │ 10-packages  48 Mint sources rebuilt,      │
│ 00-build-vm  QEMU + Apple's  │   build/ in  │              163 arch-independent fetched  │
│              hypervisor      │              │ 15-mintarm   Mint's patches, settings      │
│                              │              │              packages, locales             │
│                              │              │ 20-rootfs    debootstrap + Mint's package  │
│                              │  image, VM   │              list, both machines' halves,  │
│                              │  disk, ISO   │              local archive, first start,   │
│                              │              │              live copy, files stored once  │
│ 40-vm-image  the .utm VM     │ ◄─────────── │ 30-image     partitions, flash-kernel and  │
│                              │              │              GRUB, the VM's disk, xz       │
│                              │              │ 35-iso       live system, installer, ISO   │
└──────────────────────────────┘              └─────────────────────┬──────────────────────┘
                                                                    │ http
                 packages.linuxmint.com · ports.ubuntu.com · packages.mozilla.org
```

Three facts shape everything:

1. **Linux Mint is Ubuntu plus Linux Mint's own packages, and Linux Mint's packages are built for x86 only.** Ubuntu builds its whole archive for ARM64 (`ports.ubuntu.com`). Linux Mint's repository carries amd64 and i386 binaries, and lists its architecture-independent packages in its amd64 index. So an ARM64 Linux Mint needs Mint's compiled packages rebuilt, Mint's architecture-independent packages as they are, and Ubuntu's ARM64 archive for everything else.
2. **Linux Mint's versions must win, even when they are lower.** Some of Linux Mint's packages carry lower version numbers than Ubuntu's: its `base-files` (which makes the system Linux Mint), GNOME Calculator 41 and Zenity 3.44 (kept on GTK 3), File Roller, and others. Linux Mint pins its repository at priority 700 so that they stay; without it, an upgrade would quietly turn the system back into Ubuntu. The build keeps the same rule with a pinned local archive.
3. **A Raspberry Pi and a virtual machine start a system differently.** A Pi's firmware reads `config.txt` from a FAT partition and loads a kernel from it, with no UEFI; a virtual machine's UEFI firmware starts a boot loader from an EFI folder. Both can read the same FAT partition, so one image carries both machines' boot files and kernels, and its first start removes the half its machine does not use.

## Stage 10: Linux Mint's packages for ARM64

`build/10-packages.sh` rebuilds every Linux Mint source package that produces architecture-specific binaries in Linux Mint's own ISO: 48 of them, from Cinnamon, Muffin, Nemo and the X-Apps to Mint's builds of Ubiquity, Timeshift and Transmission. Firefox comes from Mozilla instead, and Thunderbird is not in the image. `tools/plan.py` derives the list from the ISO's package manifest and Linux Mint's index.

The sources come from `packages.linuxmint.com` through apt, which checks them against Linux Mint's signing key (fingerprint `302F 0738 F465 C153 5761 F965 A661 6109 451B BBF2`, from the `linuxmint-keyring` package's current copy). They are built in the order of their build dependencies, four layers deep: the first layer needs only Ubuntu's packages, the second needs the first (Cinnamon's settings daemon needs the rebuilt `cinnamon-desktop`), Nemo's extensions need Nemo, and Cinnamon itself comes last. Each layer's packages go into a flat apt repository (`/srv/mintarm/repo`), from which the next layer installs its build dependencies.

`dpkg-buildpackage -B` builds the architecture-specific binaries only, with `nocheck nodoc noautodbgsym`: no test suites, no documentation builds, no debug-symbol packages. Three packages build at once and share the CPUs. A failed package stops the stage once all layers have run; running it again builds only what is missing.

Linux Mint's 163 architecture-independent packages are downloaded by a throwaway apt configuration that sees Mint's repository as an amd64 machine would, with the same signature checks. Old releases' wallpaper packages are skipped.

## Stage 15: what changes for ARM

### Software Sources for ARM

Linux Mint's *Software Sources* (`mintsources`) knows only Ubuntu's x86 archive: it writes `archive.ubuntu.com` and `security.ubuntu.com`, tests mirrors by downloading their amd64 index, and skips every `ubuntu-ports` mirror in its lists. On ARM64 each of those breaks updates. The patch in `build/patches/` changes four things, on architectures other than amd64 and i386 only:

- the default base mirror becomes `http://ports.ubuntu.com/ubuntu-ports`, and the mirror list becomes `/usr/share/mintsources/ubuntu-ports.mirrors`: thirteen ports mirrors in ten countries;
- the security line is written for `ports.ubuntu.com` too, where Ubuntu publishes ARM64 security updates;
- the mirror speed test fetches the machine's own architecture's index;
- `ubuntu-ports` mirrors are no longer skipped.

The patched packages are versioned `+arm64.1` and the change is recorded in their changelogs.

### Update Manager and the kernel

Update Manager (`mintupdate`) decides whether to offer a kernel by looking for an installed kernel metapackage among those whose names start with `linux-generic`, plus `linux-virtual`. This build installs `linux-image-virtual-hwe-24.04`, which it does not know, so it concluded that no kernel line was installed and offered the first `linux-generic…` metapackage of the same version. On ARM64 that can be the 64k-page kernel (`linux-generic-64k-…`), which Apple silicon cannot start (its EFI stub refuses with *Unsupported*); installing it also made it GRUB's default entry, so the system stopped at GRUB's menu. The patch counts installed `linux-virtual…`, `linux-image-virtual…` and `linux-image-generic…` metapackages, and drops every 64k-page metapackage from consideration.

On a Raspberry Pi the running kernel is a `-raspi` one, a flavour Update Manager does not support. It then treated the system as having no kernel line at all and offered `linux-generic`, a PC kernel the Pi never starts (`flash-kernel` ignores it), along with some 300 MB. The patch makes it offer no other kernel line when the running kernel's flavour is one it does not support; the Pi's `linux-image-raspi` metapackage keeps the kernel current as an ordinary update.

### The settings packages

Three packages (files listed in the [manual](manual.md#13-what-this-build-adds-to-linux-mint)) are built from `build/mint-arm-system/`, `mint-arm-vm/` and `mint-arm-pi/`: the settings every machine shares, those of virtual machines, and those of the Raspberry Pi. One of `mint-arm-system`'s settings makes the system lighter without removing anything: dpkg leaves out the device trees of physical ARM boards that Ubuntu's generic kernel brings, about 100 MB that no virtual machine uses (`/etc/dpkg/dpkg.cfg.d/mint-arm-board-device-trees`, a `path-exclude`; the Raspberry Pi kernel keeps its own, which `flash-kernel` copies to the Pi's boot partition). `mint-arm-system` gets Mozilla's apt signing key added, after its fingerprint is checked (`35BA A0B3 3E9E B396 F59C A838 C0BA 5CE6 DC63 15A3`), and the first start's two package lists, taken from `packages.conf` (`[remove-on-vm]`, `[remove-on-pi]`). It depends on `mint-arm-vm | mint-arm-pi`, so a VM made from release 1.0.0, when it updates, takes over its VM settings into `mint-arm-vm`.

### Firefox's language packs

Ubiquity and Linux Mint's *Language Settings* install a language's Firefox translation as `firefox-locale-XX`. Ubuntu's packages of that name install the Firefox snap, which Linux Mint blocks; the installer's language step failed on them. Stage 15 makes 93 small transition packages of the same names (epoch 2, so they outrank Ubuntu's), each depending on Firefox and recommending Mozilla's `firefox-l10n-XX`.

## Stage 20: the system

`build/20-rootfs.sh` starts from nothing every time:

1. **Base.** `debootstrap` installs Ubuntu 24.04's ARM64 base from `ports.ubuntu.com`.
2. **Sources.** Linux Mint's layout (`official-package-repositories.list`), with the build's repository pinned at 700 like Linux Mint's. The three settings packages and `linuxmint-keyring` go in first, bringing Mozilla's source and Mint's key. `mint-arm-pi` brings the Raspberry Pi kernel with it, and `linux-firmware-minimal` goes in at the same time, so that it, not Ubuntu's 640 MB firmware set, answers the kernel's request for `linux-firmware`.
3. **Selection.** `select-packages.py` takes Linux Mint's own list (`casper/filesystem.manifest` from the official ISO), removes what `packages.conf` drops, adds what it keeps and adds, and leaves out what does not exist for ARM64. Both machines' halves go in: for virtual machines, Linux Mint's hardware-enablement kernel in its *virtual* flavour (without the firmware for physical hardware), the UEFI boot chain (shim, GRUB) and the guest tools; for the Raspberry Pi, Ubuntu's Raspberry Pi kernel with the Pi's firmware only, `flash-kernel`, Ubuntu's Raspberry Pi desktop settings and the bootloader updater. apt installs the result without recommends, then upgrades everything to its current update (debootstrap installs release versions).
4. **Pruning.** Every package is marked automatically installed, except `roots.txt` and the kept and added packages; `apt autoremove` then removes whatever only the dropped software needed.
5. **Settings.** Host name `mint`, US keyboard, UTC, NetworkManager for networking, GRUB's quiet start, the image's partitions by label in `/etc/fstab`, and Linux Mint's own sources.
6. **The local archive.** `select-repo.py` chooses what goes into the *Linux Mint ARM* archive at `/usr/share/mint-arm/repo` (about 57 MB): every ARM64 package rebuilt here except debug and documentation packages, the packages made for this build, any Mint package that Ubuntu ships a higher-numbered version of (so that the 700 pin applies to it), and Mint's architecture-independent packages up to 3 MB that belong to a rebuilt source, are installed, are in the original ISO's list, or are Mint applications. The archive is signed with a key made for the build (ed25519, `Linux Mint ARM local archive <mint-arm@localhost>`); only its public half goes into the system. It is packaged as `mint-arm-repo`, which also installs its source line and its 700 pin. Mint's large artwork packages (themes, icons, wallpapers) stay installed from the image alone: no Ubuntu package competes with them.
7. **The live system.** For the ISO, the system as it now stands is copied to `$W/rootfs-live`. In the copy, the first start's own removal runs for a virtual machine (`MINT_ARM_FIRST_START=packages`), so it loses the Raspberry Pi's half; the live session (`casper`) and Linux Mint's installer go back in, which the installed system never needs, with `lvm2` for the installer's LVM and encryption options, as on Linux Mint's ISO; then the installer's media are prepared: the list of live-only packages the installer removes once it has installed the system, and an offline pool with what an OEM installation puts back.
8. **The first start.** What Linux Mint's installer does in OEM mode, done here: Linux Mint's live-only packages are purged (its own list, less GRUB and shim, which virtual machines start with), `oem-config-gtk` goes back in, the temporary `oem` account is made (uid 29999, no password), and `oem-config-prepare` makes the first-start wizard the system's default target. The marker `/var/lib/mint-arm/first-start-pending` arms the first-start service, and the initrds are made again.
9. **Cleanup**, in both systems. The build's sources and pins, apt's caches and lists, logs, `/tmp`, the machine ID (emptied, so every system makes its own) and shell history are removed.
10. **Identical files.** util-linux's `hardlink` stores the identical files under `/usr` once, as hard links, when their owner, mode and extended attributes match: 124 MB in the system. When an update replaces one of them, dpkg writes it as a file of its own.

## Stage 30: the image

`build/30-image.sh` lays the image out like Ubuntu's Raspberry Pi images:

| Partition | What |
| --- | --- |
| 1: FAT32, 512 MB, `system-boot`, marked bootable | for a Raspberry Pi: its firmware (`start4.elf`, `fixup4.dat` and the rest, from `linux-firmware-raspi`), the Raspberry Pi kernel (`vmlinuz`), its initrd (`initrd.img`), the device trees of every Pi 4 and Pi 5 model and the overlays, `config.txt` and `cmdline.txt`; for a virtual machine: shim and Ubuntu's signed GRUB in `EFI/ubuntu` and at the removable-disk path `EFI/BOOT` |
| 2: ext4, `writable` | the system, with 1 GB free; it grows to fill the card or the virtual disk at the first start |

A Pi's firmware reads `config.txt`, then loads the kernel, the initrd and the board's device tree from the FAT partition, and the kernel finds its root by label (`root=LABEL=writable`). A virtual machine's UEFI firmware, finding no boot entry of its own, starts `EFI/BOOT/BOOTAA64.EFI` (shim), which starts GRUB, which starts the hardware-enablement kernel from the system partition. The stage makes a sparse image the size of the system plus a tenth and 1 GB, partitions it (MBR, which both firmwares read), and writes the system into the ext4 partition as it makes it (`mkfs.ext4 -d`): one sequential pass in directory order, so files that are alike lie together, which compresses better, and the same in every build, than copying into the mounted file system. It also leaves the blocks of a file that hold nothing but zeros unwritten, as holes, which read back as zeros: mostly padding inside programs and libraries, 164 MB that the installed system does not store until an update rewrites those files. Inside it, the initrds are made again (only now can initramfs-tools see the partition labels it checks at boot), `flash-kernel` fills the boot partition as it does on every kernel update on a Pi (told to anyway: it skips chroots and UEFI machines such as the build VM, and the newest kernel is the virtual machines' one), and `grub-install` and `update-grub` add GRUB. `config.txt` and `cmdline.txt` come from `build/pi/`, with Ubuntu's desktop settings.

The image is then checked (partitions and labels; the Pi's firmware, kernel and initrd matching the installed ones, every board's device tree; shim and GRUB, and a GRUB entry for the VM kernel; both initrds' file system check, the growing step; fstab; the first-start target and marker; the locked `oem` account; an empty machine ID; no SSH server, host keys or keys), its free blocks trimmed into holes, and compressed with `xz -9` and a 384 MiB window instead of 64, which reaches the files that are alike but far apart in the image: some 60 MB less to download, for ten minutes more of compression and 385 MB of memory to unpack it (refused over 2 GB, GitHub's limit for a release file).

**The UTM VM's disk** is a copy of the image grown to 64 GB (partition and file system), on which the first start's script runs for a virtual machine right there, so the VM carries no Raspberry Pi files; it is converted to a compressed qcow2 for stage 40. `build/qcow2-zstd.py` writes it the way `qemu-img convert -c` does, each 64 KiB cluster compressed on its own with zstd, but at level 12 rather than qemu-img's fixed level 3: 4.5 % smaller, and no slower to read back: zstd decompresses levels 6 to 12 a little faster than level 3, while levels 15 and above, smaller still, decompress more slowly. `qemu-img check` and `qemu-img compare` against the raw disk then confirm it.

With `--test-ssh`, another copy gets an SSH server for testing on a real Pi ([building](building.md#7-testing)); it is checked the same way, minus the SSH checks, and kept apart from the release files.

## Stage 35: the ISO

`build/35-iso.sh` packs the live system the way Linux Mint's own ISO is laid out: `casper/filesystem.squashfs` (zstd, level 15: levels 16 to 19 make it 2 to 6 % smaller, but Linux reads it back 2 to 6 % more slowly), `filesystem.manifest` and `filesystem.manifest-remove` (what the installer removes from the installed system), the offline pool as an apt-cdrom archive, and a GRUB boot menu (*Start*, *compatibility mode*, *OEM install*) behind shim and Ubuntu's signed GRUB CD image. `xorriso` makes it bootable from an El Torito entry and an appended EFI partition, as UEFI firmware expects; it is refused over 2 GB. The installed system gets the virtual machines' half only, with GRUB on the disk Linux Mint's installer partitions.

## The first start

`mint-arm-system` carries `/usr/lib/mint-arm/first-start` and two services that run it while `/var/lib/mint-arm/first-start-pending` exists. The image build leaves that marker, so a system updated from an earlier release never runs them.

1. **Which machine.** A device tree that names a Raspberry Pi means a Pi; anything else is treated as a virtual machine (it also covers any other UEFI machine). `mint-arm.platform=pi` or `vm` on the kernel command line decides instead, for tests.
2. **What goes.** The installed packages that match the machine's list in `/usr/share/mint-arm`: in a virtual machine the Raspberry Pi's kernel, firmware, boot tools and settings, and Bluetooth, Wi-Fi, printing and scanning; on a Pi the virtual machines' kernel, shim, GRUB, `efibootmgr` and the guest tools. apt is asked what removing them would remove, and any package that something staying still depends on stays, until removing the rest takes nothing else along. Then one `apt purge --autoremove`. dpkg removes, then purges, and initramfs-tools would rebuild the initrd after each pass; in a virtual machine its automatic updates are off meanwhile, and the initrd is built once at the end (on a Pi nothing in its initrd changes). man-db's manual index is left to its daily update.
3. **When.** `mint-arm-first-start.service` runs before the setup wizard. On a Pi, the wizard itself needs some of GRUB's tools (Ubiquity depends on them), so they stay; `mint-arm-first-start-late.service` runs again once the wizard is over and the desktop is starting, and removes them. Then the marker goes.
4. **The boot partition.** In a virtual machine, the Raspberry Pi's files leave it, it moves from `/boot/firmware` to `/boot/efi` (the UEFI system partition, as on any Ubuntu), and a 2 GB swap file gets its line in `/etc/fstab`. On a Pi, the EFI folder leaves it, and `/boot/grub` once GRUB is gone.

`journalctl -u mint-arm-first-start -u mint-arm-first-start-late` shows what happened.

## Stage 40: the ready-made VM

`build/40-vm-image.sh` takes the VM's disk from stage 30 and wraps it as a UTM package: `utm-config.plist.in` becomes the VM's `config.plist`, with fresh UUIDs and a random MAC address. The VM's first start then only runs `oem-config`, Ubiquity's first-boot half, which asks for the language, keyboard, time zone and user, then deletes the `oem` account.

## Firefox and the display

Firefox is Mozilla's ARM64 package from `packages.mozilla.org`, pinned at 1000: Mozilla's versions are numbered lower than Ubuntu's snap wrapper (`1:1snap1`), which `mint-arm-nosnap.pref` hides anyway. Linux Mint's own Firefox defaults are set by policy (`/etc/firefox/policies/policies.json`): Firefox's updater off (apt updates it), no default-browser check, and Linux Mint's settings for the Backspace key, the title bar, the language and the theme.

UTM's *GPU Supported* display is a `virtio-gpu-gl-pci` card: Mesa's VirGL driver in Linux sends OpenGL commands to QEMU, where virglrenderer replays them on ANGLE, which translates OpenGL ES to Metal. ANGLE offers OpenGL ES 3.0, so programs in the guest see OpenGL 2.1 and OpenGL ES 3.0. Through that path Firefox's WebRender lost all its text, while Cinnamon, GTK 4 and video players drew correctly; `mint-arm-vm` therefore sets `gfx.webrender.software` (WebRender's CPU renderer) and `gfx.webrender.software.opengl = false` (presented without OpenGL), in a Firefox defaults file (`/usr/lib/firefox/defaults/pref/mint-arm-vm.js`). On a Raspberry Pi that file is gone after the first start, and Firefox draws with the Pi's GPU, as Mozilla's defaults have it.

## Measured

On an M4 Max with the virtual hardware of the ready-made VM (6 cores, 8 GB, QEMU on Apple's hypervisor):

| | 1.2.2 | 1.1.0 |
| --- | --- | --- |
| The image | 1.41 GB compressed (`.img.xz`), 6.80 GB written out | 1.46 GB, 7.12 GB |
| The ready-made VM | 1.66 GB zipped | 1.82 GB |
| The ISO | 1.60 GB | (none) |
| Installed in the VM, after Linux Mint's setup and Update Manager's first refresh | 4.25 GB of files, plus the 2 GB swap file | 4.67 GB |
| Packages installed in the VM (Linux Mint on x86: 2,005) | about 1,580 | about 1,580 |
| The first start in a VM (setup on screen after power-on) | 13 s (16 s) | 18 s (23 s) |
| Kernel and services ready (`systemd-analyze`) | 1.5 to 1.7 s | 1.5 to 1.7 s |
| Memory in use with the desktop open | 0.9 GB | 0.9 GB |
| GPU display: glmark2 at 1280×720 | 1,608 (CPU-drawn display: 162), measured for 1.0.0 | |
| The Mac's CPU with the desktop idle, GPU display | 4.9 % of one core (CPU-drawn display: 13.4 %), measured for 1.0.0 | |
| The whole build (`./build.sh`, 8 cores) | about 45 minutes (see [building](building.md#3-the-stages)) | about 40 minutes |

On a Raspberry Pi: not measured yet, as this release was not tested on a real Pi. With the Pi's own kernel in QEMU on the same Mac (4 cores, 4 GB), the kernel and services are ready in 1.5 s and the desktop runs in 0.9 GB.

## Tested for each release

- The image as a virtual machine's disk (QEMU, UEFI): GRUB starts the VM kernel; the system grows to fill the disk; the first start removes the Raspberry Pi's half and moves the boot partition to `/boot/efi`; Linux Mint's setup runs and removes its temporary account; no failed systemd units; Update Manager offers no kernel change; a kernel update goes through GRUB.
- The image as a Raspberry Pi starts it, in QEMU on its own Raspberry Pi kernel: the first start removes the virtual machines' half, in its two passes; the desktop starts; a kernel update goes onto the boot partition through `flash-kernel`.
- The image on a real Raspberry Pi, through the SSH test image (not done yet): the firmware starts it; the GPU draws the desktop; Wi-Fi, Bluetooth and sound find the Pi's hardware; the system grows to fill the card; a kernel update and a restart work.
- The ready-made VM's first start runs Linux Mint's setup; every copy gets its own machine ID. The GPU-accelerated display works on UTM's own QEMU (virglrenderer and ANGLE onto Metal), with the SPICE agent running, and Firefox shows pages correctly. Written to directly, as UTM runs it (the setup, new files, packages installed and removed, a trim), its disk stays consistent for `qemu-img check`, and every package's files read back intact.
- Under Apple's Virtualization framework with Rosetta shared in, the image starts as a VM; with Ubuntu's 6.8 kernel, installed as the [manual](manual.md#8-rosetta-for-x86-64-programs) describes, x86-64 programs run.
- The ISO starts the live session in a VM; Linux Mint's installer installs the system, plainly and encrypted (LVM in LUKS); it starts with no failed systemd units, the encrypted one once its passphrase is typed at the prompt on the VM's screen.
- The one-command install, against the release's files: it finds UTM, or installs it after checking its signature and Apple's notarization; it checks the download against `SHA256SUMS` and unpacks the VM.
- Raspberry Pi Imager's list passes Imager's own JSON schema, and its address, sizes and SHA-256s match the release.
- A VM made from the previous release updates with the new `mint-arm-repo` package.
- The images carry no traces of the machine that built them.

Not tested yet: a real Raspberry Pi (every release so far was tested with the Pi's kernel in QEMU only), the VM inside UTM's own window (the same QEMU, virglrenderer and ANGLE were tested outside it; UTM's window only shows the result), VMware Fusion, Parallels Desktop, Secure Boot, and setups in languages other than English.
