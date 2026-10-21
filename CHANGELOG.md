# Changelog

## 1.0.0 — 2026-10-21

First public release, in the public domain (The Unlicense).

- **Linux Mint 22.3 "Zena" Cinnamon for ARM64**, made from the package list of Linux Mint's official x86 ISO: Cinnamon 6.6.9, the X-Apps, Linux Mint's tools and artwork, its installer with live session and OEM mode. All 48 Linux Mint source packages with compiled code are rebuilt for ARM64; Ubuntu 24.04's ARM64 archive provides the base, with Linux Mint's kernel line, Ubuntu's hardware-enablement kernel (7.0, *virtual* flavour).
- **Two ways to get it**: a ready-made UTM virtual machine, preinstalled in OEM mode so that its first start runs Linux Mint's setup, and a live/install ISO for UTM or any VM app that boots ARM64 UEFI images.
- **Light for a VM**: a 1.65 GB ISO (3.09 GB for Linux Mint's x86 ISO) and about 1,600 packages instead of 2,005. Firmware and drivers for hardware a VM does not have are left out, and the large applications are a click away.
- **GPU-accelerated desktop** on UTM's *GPU Supported* display (virglrenderer and ANGLE onto Metal); Firefox draws in software there, because it lost its text through UTM's OpenGL.
- **Updates that keep working**: Software Sources patched for Ubuntu's ARM mirrors; Update Manager patched to recognise the kernel line, so it never offers the 64k-page kernel that Apple silicon cannot start; Firefox from Mozilla's ARM64 repository; Linux Mint's packages in a local signed archive with Linux Mint's own priority, so Ubuntu's never replace them; Ubuntu's snap-only Firefox, Thunderbird and Chromium packages hidden; Firefox language packs that install Mozilla's.
- **Made for a VM**: compressed RAM swap, clipboard sharing and automatic resizing, shared folders, the QEMU guest agent, VMware Fusion's tools, a smaller journal, and Rosetta for x86-64 programs under Apple's Virtualization framework (with Ubuntu's 6.8 kernel: Rosetta does not yet run programs on newer kernels).
- **One-command build** on a Mac (`./build.sh`, about 35 minutes on an M4 Max), headless test tools including UTM's own QEMU with its GPU display, and a release script that collects the source code of every rebuilt package.
