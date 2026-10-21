# Troubleshooting

**UTM does not open the `.utm`, or reports an unsupported configuration.** Update UTM to 4.7 or newer. The `.utm` comes inside a zip: double-click the zip first, then the `.utm`.

**The VM stops at a black screen with a blinking cursor, or at the UEFI shell.** The VM found nothing to boot. For a VM made from the ISO, check that the ISO is attached (the drive button in UTM's toolbar shows the CD/DVD drive with the ISO). For an installed VM, check that its disk is listed first in the VM's settings. In the UEFI shell, `fs0:\efi\boot\bootaa64.efi` starts the boot loader by hand.

**The screen stays black after the boot menu, or the display is garbled.** Choose *compatibility mode* in the ISO's boot menu. If an installed system has the problem, switch the VM's display to `virtio-gpu-pci` in UTM's settings to rule out the GPU display.

**The VM is slow.** In the VM's settings, make sure *Use Hypervisor* is on: without it QEMU emulates the CPU, many times slower. Give it more CPU cores and memory if the Mac has them to spare. The GPU display (`virtio-gpu-gl-pci`) draws the desktop much faster than the standard one.

**A program says it needs a newer OpenGL, or crashes at start (Blender, OBS Studio, some games).** The GPU display offers OpenGL 2.1 and OpenGL ES 3.0. Start the program with `LIBGL_ALWAYS_SOFTWARE=1` in front of its command, or switch the VM's display to `virtio-gpu-pci`. See [The display](manual.md#4-the-display).

**Firefox shows pages or tabs without text.** Firefox was set to draw with the GPU. In `about:config`, set `gfx.webrender.software` back to `true` (the system's default) and restart Firefox.

**The window does not resize the desktop, or the clipboard does not work.** Both are done by `spice-vdagent`. Check that the VM's settings have *Auto Resolution* under *Display* and *Enable Clipboard Sharing* under *Sharing*, and that the agent runs in Linux (`systemctl status spice-vdagentd`). Log out and back in after changing these.

**The shared folder does not appear.** Choose the folder in UTM first (the folder button in the VM's toolbar), then open `dav://127.0.0.1:9843` in Nemo (**Ctrl+L**). It only works while the VM runs in UTM's window, because UTM serves the folder. For VirtFS and VirtioFS, see [Sharing](manual.md#5-sharing-with-the-mac).

**`sudo apt update` in the live session reports an error for the CD.** The ISO's package pool has no signed index, exactly as on Linux Mint's own ISO; the error concerns only the CD and changes nothing else. The installed system does not use the CD.

**apt wants to replace a Linux Mint package with Ubuntu's.** The local archive's priority is missing or was changed. `apt policy base-files` should show `700 file:/usr/share/mint-arm/repo` for Linux Mint's version. If it does not, reinstall the archive package: `sudo apt install --reinstall mint-arm-repo`.

**Software Sources: the mirror list has no fast mirror near you.** The list holds thirteen of Ubuntu's ARM mirrors in ten countries. Any other `ubuntu-ports` mirror works too: edit `/etc/apt/sources.list.d/official-package-repositories.list` and replace `ports.ubuntu.com/ubuntu-ports` on the four Ubuntu lines.

**An application is not in the Software Manager, or installing it fails.** It has no ARM64 build. Thunderbird and Chromium have other sources ([Installing software](manual.md#8-installing-software)); for others, look for an `aarch64` Flatpak or an ARM64 download from the maker.

**x86-64 programs do not start ("Exec format error").** Rosetta only works under Apple's Virtualization framework, not in the ready-made VM, which runs on QEMU ([Rosetta](manual.md#9-rosetta-for-x86-64-programs)).

**x86-64 programs stop with "rosetta error: unhandled auxillary vector type 29".** Rosetta cannot work with kernels 6.13 and later, the system's own included. Switch to Ubuntu's 6.8 kernel as the [manual](manual.md#9-rosetta-for-x86-64-programs) describes.

**The disk is full.** Enlarge it in UTM, then grow the partition ([Disk space](manual.md#11-disk-space)). `sudo apt clean` frees apt's downloaded packages, and `sudo journalctl --vacuum-size=50M` older logs.

**No sound.** Check the output device in Cinnamon's *Sound* settings, and that the VM's settings have a sound card (*Intel HD Audio*). UTM's sound backend is set in UTM › Settings › *Sound*.

**The first-start setup was interrupted.** Forcing the VM off during the setup is harmless: it runs again at the next start, until it has finished. To start over completely, remove the VM from UTM and unzip the download again.

**`build.sh` says the port 2299 is taken.** Another program listens there, or a build VM from another folder still runs. Choose another port with `BUILD_SSH_PORT=2300 ./build.sh`.

**`build.sh` stops in stage 10 with a download error.** `packages.linuxmint.com` is sometimes slow or unreachable for a while. Run `./build.sh` again later: it resumes with the packages that are missing. `MINT_MIRROR` can point the build at one of Linux Mint's mirrors instead.

**A package fails to build in stage 10.** The stage's output names the log (`/srv/mintarm/logs/<package>.log` in the build VM). Run `./build.sh --keep-vm` to keep the VM running and read it: `ssh -i work/build-vm/id_build -p 2299 builder@127.0.0.1`.

**`build.sh` stops in stage 40 with "install did not finish".** Mint's installer did not finish within 30 minutes; `out/.vm-work/install-serial.log` holds the install VM's console. The stage can be run again on its own: `build/40-vm-image.sh out/linuxmint-22.3-cinnamon-arm64-unofficial.iso out`.

**Something else.** Open an [issue](https://github.com/GodisGood-GodisGreat-and-GodisReal-Amen/Mint-ARM/issues) with what you did, what happened, your Mac and UTM versions, and the output of `inxi -Fxz` and `journalctl -b -p warning` from the VM. Please don't take problems with this build to the Linux Mint team: they did not make it.
