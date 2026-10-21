# How Linux Mint ARM is made

A map of the build for anyone who wants to change it.

## The shape of it

```
the Mac (zsh)                                    build VM: Ubuntu 24.04 ARM64 (bash)
┌──────────────────────────────┐     ssh      ┌────────────────────────────────────────────┐
│ build.sh                     │ ───────────► │ 10-packages  48 Mint sources rebuilt,      │
│ 00-build-vm  QEMU + Apple's  │  build/ in   │              163 arch-independent fetched  │
│              hypervisor      │              │ 15-mintarm   Software Sources patch,       │
│                              │              │              mint-arm-system, locales      │
│                              │   ISO out    │ 20-rootfs    debootstrap + Mint's package  │
│ 40-vm-image  Mint's installer│ ◄─────────── │              list, local archive, pool     │
│              in OEM mode     │              │ 30-iso       squashfs, shim + GRUB, xorriso│
│              → the .utm VM   │              │                                            │
└──────────────────────────────┘              └─────────────────────┬──────────────────────┘
                                                                    │ http
                 packages.linuxmint.com · ports.ubuntu.com · packages.mozilla.org
```

Two facts shape everything:

1. **Linux Mint is Ubuntu plus Linux Mint's own packages, and Linux Mint's packages are built for x86 only.** Ubuntu builds its whole archive for ARM64 (`ports.ubuntu.com`). Linux Mint's repository carries amd64 and i386 binaries, and lists its architecture-independent packages in its amd64 index. So an ARM64 Linux Mint needs Mint's compiled packages rebuilt, Mint's architecture-independent packages as they are, and Ubuntu's ARM64 archive for everything else.
2. **Linux Mint's versions must win, even when they are lower.** Some of Linux Mint's packages carry lower version numbers than Ubuntu's: its `base-files` (which makes the system Linux Mint), GNOME Calculator 41 and Zenity 3.44 (kept on GTK 3), File Roller, and others. Linux Mint pins its repository at priority 700 so that they stay; without it, an upgrade would quietly turn the system back into Ubuntu. The build keeps the same rule with a pinned local archive.

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

### mint-arm-system

The settings package (files listed in the [manual](manual.md#14-what-this-build-adds-to-linux-mint)) is built from `build/mint-arm-system/` with Mozilla's apt signing key added, after its fingerprint is checked (`35BA A0B3 3E9E B396 F59C A838 C0BA 5CE6 DC63 15A3`).

### Firefox's language packs

Ubiquity and Linux Mint's *Language Settings* install a language's Firefox translation as `firefox-locale-XX`. Ubuntu's packages of that name install the Firefox snap, which Linux Mint blocks; the installer's language step failed on them. Stage 15 makes 93 small transition packages of the same names (epoch 2, so they outrank Ubuntu's), each depending on Firefox and recommending Mozilla's `firefox-l10n-XX`.

## Stage 20: the system

`build/20-rootfs.sh` starts from nothing every time:

1. **Base.** `debootstrap` installs Ubuntu 24.04's ARM64 base from `ports.ubuntu.com`.
2. **Sources.** Linux Mint's layout (`official-package-repositories.list`), with the build's repository pinned at 700 like Linux Mint's. `mint-arm-system` and `linuxmint-keyring` go in first, bringing Mozilla's source and Mint's key.
3. **Selection.** `select-packages.py` takes Linux Mint's own list (`casper/filesystem.manifest` from the official ISO), removes what `packages.conf` drops, adds what it keeps and adds, and leaves out what does not exist for ARM64. Linux Mint's hardware-enablement kernel is installed in its *virtual* flavour, without the firmware for physical hardware. apt installs the result without recommends, then upgrades everything to its current update (debootstrap installs release versions).
4. **Pruning.** Every package is marked automatically installed, except `roots.txt` and the kept and added packages; `apt autoremove` then removes whatever only the dropped software needed. This is how 2,005 packages become about 1,600.
5. **Settings.** Host name `mint`, US keyboard, UTC, NetworkManager for networking, GRUB's quiet boot, and Linux Mint's own sources.
6. **The local archive.** `select-repo.py` chooses what goes into the *Linux Mint ARM* archive at `/usr/share/mint-arm/repo` (about 56 MB): every ARM64 package rebuilt here except debug and documentation packages, the packages made for this build, any Mint package that Ubuntu ships a higher-numbered version of (so that the 700 pin applies to it), and Mint's architecture-independent packages up to 3 MB that belong to a rebuilt source, are installed, or are Mint applications. The archive is signed with a key made for the build (ed25519, `Linux Mint ARM local archive <mint-arm@localhost>`); only its public half goes into the system. It is packaged as `mint-arm-repo`, which also installs its source line and its 700 pin. Mint's large artwork packages (themes, icons, wallpapers) stay installed from the image alone: no Ubuntu package competes with them.
7. **Installer media.** The list of packages the installer removes after copying the system (Linux Mint's own list, less GRUB and shim, which an ARM64 install keeps), and the offline pool of packages an OEM install adds back (`oem-config-gtk` and the parts of Ubiquity it uses), found by asking apt what installing `oem-config-gtk` would download on the installed system.
8. **Cleanup.** The build's sources and pins, apt's caches and lists, logs, `/tmp`, the machine ID (emptied, so every system makes its own) and shell history are removed.

## Stage 30: the ISO

`build/30-iso.sh` lays the ISO out like Linux Mint's:

| Path | What |
| --- | --- |
| `casper/filesystem.squashfs` | the system, zstd level 19 in 1 MB blocks |
| `casper/vmlinuz`, `casper/initrd.lz` | the kernel, and the initramfs with casper, the live-session boot code |
| `casper/filesystem.manifest`, `filesystem.manifest-remove`, `filesystem.size` | what the installer reads |
| `pool/`, `dists/noble/` | the installer's offline packages, in apt-cdrom layout |
| `EFI/boot/bootaa64.efi`, `mmaa64.efi`, `grubaa64.efi` | shim, its key manager, and Ubuntu's signed GRUB for discs |
| `boot/grub/` | the boot menu, GRUB's modules and font |
| `.disk/` | the disc's identity, which GRUB and the installer use to find it |
| `md5sum.txt` | the checksums the live session verifies |

ARM64 boots by UEFI only. `xorriso` appends a FAT EFI system partition holding shim and GRUB, referenced both from the El Torito boot catalogue (for CD and DVD drives, real or virtual) and from a GPT entry (for the ISO written to a USB stick or attached as a disk). The firmware starts shim, shim starts Ubuntu's signed GRUB, GRUB finds the disc by its `.disk/info` and starts the kernel. The chain is the one Ubuntu signs for Secure Boot, though Secure Boot itself has not been tested.

## Stage 40: the ready-made VM

`build/40-vm-image.sh` installs the ISO the way a manufacturer would. It takes the ISO's kernel and initramfs and appends a small archive holding `/preseed.cfg` (`build/utm-oem.seed`; an appended archive must start on a 4-byte boundary). QEMU boots that kernel directly with `automatic-ubiquity oem-config/enable=true`: Ubiquity installs unattended in OEM mode, onto a fresh 64 GB disk, as a temporary `oem` user. Its last command prepares the first-boot wizard, locks the temporary account, empties the machine ID, deletes the random seed and trims the free space, then powers off.

`qemu-img convert` packs the disk into a compressed qcow2 (zstd clusters, which read back faster than zlib ones). `utm-config.plist.in` becomes the VM's `config.plist`, with fresh UUIDs and a random MAC address, and both go into a `.utm` package. Its first start runs `oem-config`, Ubiquity's first-boot half, which asks for the language, keyboard, time zone and user, then deletes the `oem` account.

## Firefox and the display

Firefox is Mozilla's ARM64 package from `packages.mozilla.org`, pinned at 1000: Mozilla's versions are numbered lower than Ubuntu's snap wrapper (`1:1snap1`), which `mint-arm-nosnap.pref` hides anyway. Linux Mint's own Firefox defaults are set by policy (`/etc/firefox/policies/policies.json`): Firefox's updater off (apt updates it), no default-browser check, and Linux Mint's settings for the Backspace key, the title bar, the language and the theme.

UTM's *GPU Supported* display is a `virtio-gpu-gl-pci` card: Mesa's VirGL driver in Linux sends OpenGL commands to QEMU, where virglrenderer replays them on ANGLE, which translates OpenGL ES to Metal. ANGLE offers OpenGL ES 3.0, so programs in the guest see OpenGL 2.1 and OpenGL ES 3.0. Through that path Firefox's WebRender lost all its text, while Cinnamon, GTK 4 and video players drew correctly; the policy therefore sets `gfx.webrender.software` (WebRender's CPU renderer) and `gfx.webrender.software.opengl = false` (presented without OpenGL).

## Measured

On an M4 Max with the virtual hardware of the ready-made VM (6 cores, 8 GB, QEMU on Apple's hypervisor):

| | |
| --- | --- |
| ISO | 1.65 GB (Linux Mint's x86 ISO: 3.09 GB) |
| Installed | 4.65 GB of files (Linux Mint on x86: 8.35 GB), plus the 2 GB swap file |
| Packages installed | about 1,600 (Linux Mint on x86: 2,005) |
| Live ISO, boot menu to the Cinnamon desktop | 10 s |
| Installed system, kernel and services ready (`systemd-analyze`) | 1.5 s |
| Memory in use with the desktop open | 0.9 GB |
| Installing from the ISO | about 5 minutes |
| GPU display: glmark2 at 1280×720 | 1,608 (CPU-drawn display: 162) |
| The Mac's CPU with the desktop idle, GPU display | 4.9 % of one core (CPU-drawn display: 13.4 %) |
| The whole build (`./build.sh`, 8 cores) | about 35 minutes (see [building](building.md#3-the-stages)) |

## Tested for each release

- The ISO boots by UEFI to the live desktop; the installer installs unattended; the installed system boots with no failed systemd units.
- The ready-made VM's first start runs Linux Mint's setup, which removes the temporary account; every copy gets its own machine ID.
- A simulated full upgrade replaces no Linux Mint package with Ubuntu's, and Update Manager offers no kernel change on a fresh system.
- Software Sources lists Ubuntu's ARM mirrors and its speed test works; Update Manager installs updates.
- Firefox shows pages correctly; the GPU-accelerated display works on UTM's own QEMU (virglrenderer and ANGLE onto Metal), with the SPICE agent running.
- Under Apple's Virtualization framework with Rosetta shared in, the live ISO and the installed system start; the Rosetta service registers it at each start; with Ubuntu's 6.8 kernel, installed as the [manual](manual.md#9-rosetta-for-x86-64-programs) describes, x86-64 programs run.
- The images carry no traces of the machine that built them.

Not tested yet: the VM inside UTM's own window (the same QEMU, virglrenderer and ANGLE were tested outside it; UTM's window only shows the result), VMware Fusion, Parallels Desktop, Secure Boot, and graphical installs in languages other than English.
