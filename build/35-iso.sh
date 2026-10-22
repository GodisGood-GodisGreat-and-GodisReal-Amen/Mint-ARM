#!/bin/bash
# Linux Mint ARM build, stage 35 (in the build VM): pack the live system that 20-rootfs.sh made in
# $W/rootfs-live (the system for virtual machines, with the live session and Linux Mint's
# installer) into a UEFI-bootable arm64 live/install ISO, for those who would rather install it
# themselves. Same layout as Linux Mint's own ISO (casper live system, Ubiquity installer, offline
# pool), with the arm64 UEFI boot chain: shim -> signed GRUB (CD image) -> kernel.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
R=$W/rootfs-live
IMG=$W/iso
OUT=${OUT:-$W/out}
NAME="Linux Mint 22.3 Cinnamon ARM64"
ISO=$OUT/linuxmint-22.3-cinnamon-arm64-unofficial.iso
SQUASHFS_COMP=${SQUASHFS_COMP:-zstd}
SIZE_LIMIT=2147483648    # GitHub's limit for one release file

in_root() { sudo chroot "$R" /usr/bin/env -i HOME=/root LANG=C.UTF-8 PATH=/usr/sbin:/usr/bin:/sbin:/bin "$@"; }

prepare_tree() {
  [ -x "$R/usr/bin/ubiquity" ] || { echo "no live system in $R: run 20-rootfs.sh first" >&2; exit 1; }
  for tool in mksquashfs xorriso mcopy mkfs.vfat apt-ftparchive; do
    command -v $tool > /dev/null || { echo "$tool is missing in the build VM" >&2; exit 1; }
  done
  sudo rm -rf "$IMG" && mkdir -p "$IMG"/{.disk,casper,boot/grub/fonts,EFI/boot} "$OUT"
  rm -f "$ISO" "$ISO.sha256"
  local kver; kver=$(ls "$R"/boot/vmlinuz-* | sed 's|.*/vmlinuz-||' | sort -V | tail -1)
  sudo cp "$R/boot/vmlinuz-$kver" "$IMG/casper/vmlinuz"
  sudo cp "$R/boot/initrd.img-$kver" "$IMG/casper/initrd.lz"
  sudo chown "$(id -u):$(id -g)" "$IMG"/casper/*
  echo "$NAME \"Zena\" - Release arm64 $(date -u +%Y%m%d)" > "$IMG/.disk/info"
  echo "full_cd/single" > "$IMG/.disk/cd_type"
  echo "https://www.linuxmint.com/rel_zena.php" > "$IMG/.disk/release_notes_url"
  printf '# Used for troubleshooting.\n# This filename is unique to Mint ISO images.' > "$IMG/.disk/mint_iso"
  : > "$IMG/.disk/base_installable"
}

manifests() {
  in_root dpkg-query -W --showformat='${Package}\t${Version}\n' > "$IMG/casper/filesystem.manifest"
  cp "$W/filesystem.manifest-remove" "$IMG/casper/filesystem.manifest-remove"
  sudo du -sx --block-size=1 "$R" | cut -f1 > "$IMG/casper/filesystem.size"
}

squashfs() {
  log "squashfs ($SQUASHFS_COMP)"
  local opts=(-comp "$SQUASHFS_COMP" -b 1M -noappend -no-progress -wildcards -e 'mnt/mintarm-repo')
  [ "$SQUASHFS_COMP" = zstd ] && opts+=(-Xcompression-level 19)
  [ "$SQUASHFS_COMP" = xz ] && opts+=(-Xbcj arm64)
  sudo mksquashfs "$R" "$IMG/casper/filesystem.squashfs" "${opts[@]}" > "$W/logs/mksquashfs.log"
  sudo chown "$(id -u):$(id -g)" "$IMG/casper/filesystem.squashfs"
}

# Offline pool for the installer (prepared by 20-rootfs.sh) as an apt-cdrom style archive
pool() {
  mkdir -p "$IMG/pool/main" "$IMG/dists/noble/main/binary-arm64"
  cp "$W"/pool/*.deb "$IMG/pool/main/"
  (cd "$IMG" && apt-ftparchive packages pool/main > dists/noble/main/binary-arm64/Packages \
     && gzip -9nkf dists/noble/main/binary-arm64/Packages \
     && apt-ftparchive -o APT::FTPArchive::Release::Origin="Linux Mint" -o APT::FTPArchive::Release::Label="Linux Mint" \
          -o APT::FTPArchive::Release::Suite=noble -o APT::FTPArchive::Release::Codename=noble \
          -o APT::FTPArchive::Release::Version=22.3 -o APT::FTPArchive::Release::Architectures=arm64 \
          -o APT::FTPArchive::Release::Components=main release dists/noble > dists/noble/Release)
  log "pool: $(ls "$IMG/pool/main" | wc -l) packages"
}

bootloader() {
  # shim and Ubuntu's signed GRUB CD image (finds the disc through /.disk/info)
  cp "$R/usr/lib/shim/shimaa64.efi.signed.latest" "$IMG/EFI/boot/bootaa64.efi" 2>/dev/null \
    || cp "$R/usr/lib/shim/shimaa64.efi.signed" "$IMG/EFI/boot/bootaa64.efi"
  cp "$R/usr/lib/shim/mmaa64.efi" "$IMG/EFI/boot/mmaa64.efi"
  cp "$R/usr/lib/grub/arm64-efi-signed/gcdaa64.efi.signed" "$IMG/EFI/boot/grubaa64.efi"
  cp -r "$R/usr/lib/grub/arm64-efi" "$IMG/boot/grub/"
  rm -f "$IMG"/boot/grub/arm64-efi/*.module
  cp "$R/usr/share/grub/unicode.pf2" "$IMG/boot/grub/fonts/unicode.pf2"
  # console=tty1: the kernel's console on the VM's screen rather than the serial port its firmware
  # names (no splash, and messages nobody sees, otherwise); before "--", so that the installer does
  # not copy it to the installed system, which has it from mint-arm-vm
  local args="boot=casper username=mint hostname=mint iso-scan/filename=\${iso_path} console=tty1"
  cat > "$IMG/boot/grub/grub.cfg" <<EOF
loadfont unicode

set color_normal=white/black
set color_highlight=black/light-gray
set timeout=10

menuentry "Start $NAME" --class linuxmint {
	set gfxpayload=keep
	linux	/casper/vmlinuz $args quiet splash --
	initrd	/casper/initrd.lz
}
menuentry "Start $NAME (compatibility mode)" {
	linux	/casper/vmlinuz $args nomodeset nosplash --
	initrd	/casper/initrd.lz
}
menuentry "OEM install (for manufacturers)" {
	set gfxpayload=keep
	linux	/casper/vmlinuz oem-config/enable=true only-ubiquity $args quiet splash --
	initrd	/casper/initrd.lz
}
menuentry 'Boot from next volume' {
	exit 1
}
menuentry 'UEFI Firmware Settings' {
	fwsetup
}
EOF
  echo "source /boot/grub/grub.cfg" > "$IMG/boot/grub/loopback.cfg"
  # El Torito / GPT EFI system partition image
  rm -f "$W/efi.img"
  mkfs.vfat -C -n MINT_EFI "$W/efi.img" 8192 > /dev/null
  mmd -i "$W/efi.img" ::/EFI ::/EFI/boot
  mcopy -i "$W/efi.img" "$IMG"/EFI/boot/*.efi ::/EFI/boot/
}

make_iso() {
  (cd "$IMG" && find . -type f ! -name md5sum.txt ! -name boot.catalog -print0 | sort -z \
     | xargs -0 md5sum > md5sum.txt)
  rm -f "$ISO"
  xorriso -as mkisofs -r -J -joliet-long -l -iso-level 3 \
    -V "$NAME" -A "Linux Mint Live" -publisher "Linux Mint ARM (unofficial)" \
    -partition_offset 16 \
    -append_partition 2 0xef "$W/efi.img" -appended_part_as_gpt \
    -c boot.catalog -e --interval:appended_partition_2:all:: -no-emul-boot \
    -o "$ISO" "$IMG" > "$W/logs/xorriso.log" 2>&1
  [ "$(stat -c %s "$ISO")" -le "$SIZE_LIMIT" ] || { echo "$(basename "$ISO") is over GitHub's 2 GiB limit for a release file" >&2; exit 1; }
  (cd "$OUT" && sha256sum "$(basename "$ISO")" > "$(basename "$ISO").sha256")
  log "ISO: $ISO ($(du -h "$ISO" | cut -f1)); squashfs $(du -h "$IMG/casper/filesystem.squashfs" | cut -f1)"
}

prepare_tree
manifests
squashfs
pool
bootloader
make_iso
