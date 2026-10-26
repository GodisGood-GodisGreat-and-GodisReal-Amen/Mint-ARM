#!/bin/bash
# Linux Mint ARM build, stage 30 (in the build VM): the disk images. The system that 20-rootfs.sh
# assembled in $W/rootfs goes into one image that starts both on a Raspberry Pi and in a virtual
# machine, laid out like Ubuntu's Raspberry Pi images: an MBR with a FAT32 boot partition
# labelled "system-boot" and an ext4 system partition labelled "writable", which grows to fill
# the card (or the virtual disk) at the first start. The boot partition serves both machines:
#   a Raspberry Pi's firmware reads config.txt, then loads Ubuntu's Raspberry Pi kernel, its
#   initrd and the board's device tree from it (put there by flash-kernel, as on every kernel
#   update on the Pi);
#   a virtual machine's UEFI firmware starts shim and GRUB from its EFI folder, and GRUB the
#   hardware-enablement kernel from the system partition.
# The first start removes the half the machine does not use (mint-arm-system's first-start
# service). Writes to $OUT:
#   linuxmint-22.3-cinnamon-arm64-unofficial.img.xz (+ .sha256)   the image
#   linuxmint-22.3-cinnamon-arm64-unofficial-vm.qcow2 (+ .sha256)  the disk of the ready-made UTM
#       VM (40-vm-image.sh): the image grown to 64 GB, its first start in a VM already done
#   TEST_SSH_KEY=FILE  also make a test image from a copy, reachable over SSH with that public
#                      key (see make_test_image); it goes to $W/out-test, never to $OUT
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
R=$W/rootfs
OUT=${OUT:-$W/out}
NAME=linuxmint-22.3-cinnamon-arm64-unofficial
D=$W/image
IMG=$D/$NAME.img
MNT=$D/mnt
BOOT_MIB=512
VM_DISK=64G
SIZE_LIMIT=2147483648    # GitHub's limit for one release file
# every board the image is for needs its device tree on the boot partition
DTBS="bcm2711-rpi-4-b bcm2711-rpi-400 bcm2711-rpi-cm4 bcm2712-rpi-5-b bcm2712d0-rpi-5-b bcm2712-rpi-500
      bcm2712-rpi-cm5-cm5io bcm2712-rpi-cm5l-cm5io"

LOOP=
detach() {
  local m
  for m in "$MNT/boot/efi" "$MNT/boot/firmware" "$MNT/sys" "$MNT/proc" "$MNT/dev/pts" "$MNT/dev" "$MNT"; do
    if mountpoint -q "$m"; then sudo umount "$m" 2> /dev/null || sudo umount -l "$m"; fi
  done
  if [ -n "$LOOP" ]; then sudo losetup -d "$LOOP"; LOOP=; fi
}
trap detach EXIT

attach() {   # IMAGE: mount its system partition at $MNT and its boot partition inside it
  LOOP=$(sudo losetup -P --show -f "$1")
  sudo mkdir -p "$MNT"
  sudo mount "${LOOP}p2" "$MNT"
  sudo mkdir -p "$MNT/boot/firmware"
  sudo mount "${LOOP}p1" "$MNT/boot/firmware"
}
in_image() {
  local d
  for d in dev dev/pts proc sys; do mountpoint -q "$MNT/$d" || sudo mount --bind "/$d" "$MNT/$d"; done
  sudo chroot "$MNT" /usr/bin/env -i HOME=/root TERM=dumb LANG=C.UTF-8 \
    PATH=/usr/sbin:/usr/bin:/sbin:/bin DEBIAN_FRONTEND=noninteractive "$@"
}
no_services() {   # on|off: package scripts in the image must not start or stop services here
  if [ "$1" = on ]; then
    printf '#!/bin/sh\nexit 101\n' | sudo tee "$MNT/usr/sbin/policy-rc.d" > /dev/null
    sudo chmod 755 "$MNT/usr/sbin/policy-rc.d"
  else
    sudo rm -f "$MNT/usr/sbin/policy-rc.d"
  fi
}
no_os_prober() {   # on|off: os-prober would add the build VM's own Ubuntu to GRUB's menu
  if [ "$1" = on ]; then sudo chmod -x "$MNT/etc/grub.d/30_os-prober"; else sudo chmod +x "$MNT/etc/grub.d/30_os-prober"; fi
}
leave_image() {   # unmount everything, punching the freed blocks out of the image file
  local d
  for d in boot/efi sys proc dev/pts dev; do
    if mountpoint -q "$MNT/$d"; then sudo umount "$MNT/$d" 2> /dev/null || sudo umount -l "$MNT/$d"; fi
  done
  sudo fstrim "$MNT/boot/firmware" 2> /dev/null || true
  sudo fstrim "$MNT"
  detach
}
compress() {   # IMAGE OUTPUT.img.xz [XZ_OPTION...] (every core: xz would use half of them under its default memory cap)
  local image=$1 out=$2; shift 2
  xz -T0 -9 "$@" --memlimit-compress=75% -c "$image" > "$out.part"
  mv "$out.part" "$out"
  (cd "$(dirname "$out")" && sha256sum "$(basename "$out")" > "$(basename "$out").sha256")
  [ "$(stat -c %s "$out")" -le "$SIZE_LIMIT" ] \
    || { echo "$(basename "$out") is over GitHub's 2 GiB limit for a release file" >&2; exit 1; }
}
kernel() {   # FLAVOUR: the newest installed kernel of that flavour (raspi, generic)
  in_image linux-version list | grep -- "-$1\$" | sort -V | tail -1
}

make_image() {
  [ -x "$R/usr/sbin/flash-kernel" ] && [ -x "$R/usr/sbin/grub-install" ] \
    || { echo "no system in $R: run 20-rootfs.sh first" >&2; exit 1; }
  command -v mkfs.vfat > /dev/null || sudo apt-get install -y -qq --no-install-recommends dosfstools > /dev/null
  local used root_mib total_mib stale kraspi
  used=$(sudo du -sxm "$R" | cut -f1)
  # the system, a tenth more for the file system itself, and 1 GiB to spare (the first start
  # grows it to the whole card)
  root_mib=$(( (used * 11 / 10 + 1024 + 3) / 4 * 4 ))
  total_mib=$(( 1 + BOOT_MIB + root_mib ))
  detach
  for stale in $(sudo losetup -n -O NAME -j "$IMG" 2> /dev/null); do sudo losetup -d "$stale"; done
  rm -rf "$D" "$OUT"/linuxmint-22.3-cinnamon-arm64-* && mkdir -p "$D" "$OUT"
  truncate -s "${total_mib}M" "$IMG"
  sfdisk -q "$IMG" <<EOF
label: dos
unit: sectors
start=2048, size=$(( BOOT_MIB * 2048 )), type=c, bootable
start=$(( (1 + BOOT_MIB) * 2048 )), type=83
EOF
  LOOP=$(sudo losetup -P --show -f "$IMG")
  # (a lowercase label, as on Ubuntu's images; mkfs.fat warns about those)
  sudo mkfs.vfat -F 32 -n system-boot "${LOOP}p1" 2>&1 | { grep -v -e 'lowercase labels' -e '^mkfs.fat ' || true; }
  # The system goes in as the file system is made: one sequential pass in directory order, so files
  # that are alike lie together. That compresses better, and the same in every build, than copying
  # into the mounted file system, where where each file lands depends on timing.
  log "writing the system ($used MiB) into a $total_mib MiB image"
  sudo mkfs.ext4 -q -L writable -d "$R" "${LOOP}p2"
  sudo losetup -d "$LOOP" && LOOP=
  attach "$IMG"
  sudo rmdir "$MNT/mnt/mintarm-repo" 2> /dev/null || true
  # The initrds again, now that the partitions exist: in the system's own folder, initramfs-tools
  # cannot find LABEL=writable, so it leaves out the file system check of the system partition.
  in_image update-initramfs -u -k all > "$W/logs/image-initramfs.log" 2>&1 \
    || { tail -20 "$W/logs/image-initramfs.log"; exit 1; }
  # The Raspberry Pi's half. flash-kernel's "pi" method copies the same files for every model:
  # the kernel and its initrd, the boot firmware, all device trees and overlays. It skips chroots
  # and UEFI machines (such as this build VM) unless told otherwise, and the newest kernel here
  # is the virtual machines' one, so it is told which kernel too.
  kraspi=$(kernel raspi)
  in_image env FK_FORCE=yes FK_IGNORE_EFI=yes FK_MACHINE="Raspberry Pi 4 Model B" flash-kernel "$kraspi" \
    > "$W/logs/image-flash-kernel.log" 2>&1 || { tail -20 "$W/logs/image-flash-kernel.log"; exit 1; }
  # It also links the Pi 4's device tree as /boot/dtb, for U-Boot. GRUB would hand that to the
  # virtual machines' kernel, which then stops at its start; the Pi's firmware does not use it.
  sudo rm -rf "$MNT"/boot/dtb "$MNT"/boot/dtb-* "$MNT/boot/dtbs"
  sudo install -m 644 "$HERE/pi/config.txt" "$HERE/pi/cmdline.txt" "$MNT/boot/firmware/"
  # The virtual machines' half: shim and Ubuntu's signed GRUB in the partition's EFI folder, both
  # where an installed Ubuntu keeps them (EFI/ubuntu) and at the path UEFI firmware starts from
  # removable disks (EFI/BOOT), so the image starts in any VM without a firmware boot entry.
  sudo mkdir -p "$MNT/boot/efi" && sudo mount --bind "$MNT/boot/firmware" "$MNT/boot/efi"
  no_os_prober on
  {
    in_image grub-install --target=arm64-efi --efi-directory=/boot/efi --uefi-secure-boot --no-nvram \
      && in_image grub-install --target=arm64-efi --efi-directory=/boot/efi --uefi-secure-boot --no-nvram --removable \
      && in_image update-grub
  } > "$W/logs/image-grub.log" 2>&1 || { tail -20 "$W/logs/image-grub.log"; exit 1; }
  no_os_prober off
  sudo umount "$MNT/boot/efi"
  check_image
}

check_image() {
  local kraspi kvm f initrd problems=
  kraspi=$(kernel raspi) kvm=$(kernel generic)
  if [ -z "${TRIMMED:-}" ] || [ "$TRIMMED" = pi ]; then
    [ -n "$kraspi" ] || problems+=" no Raspberry Pi kernel;"
    for f in bootcode.bin start4.elf fixup4.dat vmlinuz initrd.img config.txt cmdline.txt \
             overlays/vc4-kms-v3d.dtbo $(printf '%s.dtb ' $DTBS); do
      [ -s "$MNT/boot/firmware/$f" ] || problems+=" no /boot/firmware/$f;"
    done
    sudo cmp -s "$MNT/boot/firmware/vmlinuz" "$MNT/boot/vmlinuz-$kraspi" || problems+=" vmlinuz is not $kraspi;"
    sudo cmp -s "$MNT/boot/firmware/initrd.img" "$MNT/boot/initrd.img-$kraspi" || problems+=" initrd.img is not $kraspi's;"
    initrd=$(in_image lsinitramfs "/boot/initrd.img-$kraspi")
    grep -q 'scripts/local-bottom/growroot$' <<< "$initrd" || problems+=" the Pi's initrd does not grow the system;"
    grep -q 'sbin/fsck.ext4$' <<< "$initrd" || problems+=" the Pi's initrd does not check the system partition;"
  fi
  if [ -z "${TRIMMED:-}" ] || [ "$TRIMMED" = vm ]; then
    [ -n "$kvm" ] || problems+=" no virtual machine kernel;"
    for f in EFI/BOOT/BOOTAA64.EFI EFI/BOOT/grubaa64.efi EFI/ubuntu/shimaa64.efi EFI/ubuntu/grub.cfg; do
      [ -s "$MNT/boot/firmware/$f" ] || problems+=" no $f;"
    done
    sudo grep -q "linux[[:space:]].*/vmlinuz-$kvm " "$MNT/boot/grub/grub.cfg" || problems+=" GRUB does not start $kvm;"
    ! sudo grep -q '^[[:space:]]*devicetree[[:space:]]' "$MNT/boot/grub/grub.cfg" || problems+=" GRUB passes a device tree;"
    ! sudo grep -q "^menuentry .*(on /dev/" "$MNT/boot/grub/grub.cfg" || problems+=" GRUB lists the build VM's system;"
    [ -x "$MNT/etc/grub.d/30_os-prober" ] || problems+=" os-prober is left off;"
    grep -q 'sbin/fsck.ext4$' <<< "$(in_image lsinitramfs "/boot/initrd.img-$kvm")" \
      || problems+=" the VM kernel's initrd does not check the system partition;"
  fi
  [ "$(sudo blkid -s LABEL -o value "${LOOP}p1")" = system-boot ] || problems+=" boot partition label;"
  [ "$(sudo blkid -s LABEL -o value "${LOOP}p2")" = writable ] || problems+=" system partition label;"
  grep -q '^LABEL=writable[[:space:]]' "$MNT/etc/fstab" && grep -q '^LABEL=system-boot[[:space:]]' "$MNT/etc/fstab" \
    || problems+=" fstab;"
  readlink "$MNT/etc/systemd/system/default.target" | grep -q 'oem-config\.target$' \
    || problems+=" does not start into the first-start setup;"
  in_image passwd -S oem | grep -q '^oem L ' || problems+=" the oem account has a password;"
  [ ! -s "$MNT/etc/machine-id" ] || problems+=" machine-id is set;"
  if [ -z "${TRIMMED:-}" ]; then
    [ -e "$MNT/var/lib/mint-arm/first-start-pending" ] || problems+=" the first start is not pending;"
  fi
  if [ -z "${TESTING:-}" ]; then
    in_image dpkg-query -W -f '${db:Status-Abbrev}' openssh-server 2> /dev/null | grep -q '^ii' \
      && problems+=" an SSH server is installed;"
    ! compgen -G "$MNT/etc/ssh/ssh_host_*" > /dev/null || problems+=" SSH host keys;"
    [ -z "$(sudo find "$MNT/root" "$MNT/home" -name authorized_keys)" ] || problems+=" an authorized_keys file;"
  fi
  [ -z "$problems" ] || { echo "the image is not right:$problems" >&2; exit 1; }
  log "image checked: ${TRIMMED:-both} (${kraspi:-} ${kvm:-}), $(du -sh "$MNT/boot/firmware" | cut -f1) on the boot partition"
}

# The ready-made UTM VM's disk: the image on a 64 GB disk, its first start in a virtual machine
# done here, so the VM carries no Raspberry Pi files (it runs the setup wizard at its first start).
make_vm_disk() {
  local vm=$D/vm.img
  log "preparing the virtual machine's disk"
  command -v qemu-img > /dev/null || sudo apt-get install -y -qq --no-install-recommends qemu-utils > /dev/null
  cp --sparse=always "$IMG" "$vm"
  truncate -s "$VM_DISK" "$vm"
  echo ', +' | sfdisk -q -N 2 --no-reread "$vm" 2>&1 | { grep -v 'Re-reading\|re-read' || true; }
  LOOP=$(sudo losetup -P --show -f "$vm")
  sudo e2fsck -fp "${LOOP}p2" > /dev/null
  sudo resize2fs "${LOOP}p2" > /dev/null 2>&1
  sudo losetup -d "$LOOP" && LOOP=
  attach "$vm"
  no_services on
  no_os_prober on
  in_image env MINT_ARM_PLATFORM=vm /usr/lib/mint-arm/first-start > "$W/logs/vm-first-start.log" 2>&1 \
    || { tail -20 "$W/logs/vm-first-start.log"; exit 1; }
  no_os_prober off
  no_services off
  grep -E '^(removing|mint-arm)' "$W/logs/vm-first-start.log" | sed 's/^/  /'
  TRIMMED=vm check_image
  if in_image dpkg-query -W -f '${Package}\n' 'linux-image-*-raspi' 2> /dev/null | grep -q .; then
    echo "the virtual machine's disk still has the Raspberry Pi kernel" >&2; exit 1
  fi
  # the boot partition is mounted at /boot/efi from now on (the first start changed fstab)
  sudo fstrim "$MNT/boot/firmware" 2> /dev/null || true
  sudo umount "$MNT/boot/firmware" && sudo rmdir "$MNT/boot/firmware"
  leave_image
  # a compressed qcow2 as qemu-img makes it, with zstd at level 12 instead of its fixed 3: smaller,
  # and no slower to read back; then checked by qemu-img against the raw disk
  python3 "$HERE/qcow2-zstd.py" --level 12 "$vm" "$OUT/$NAME-vm.qcow2"
  qemu-img check -q "$OUT/$NAME-vm.qcow2" || { echo "the virtual machine's qcow2 is not consistent" >&2; exit 1; }
  qemu-img compare -q "$vm" "$OUT/$NAME-vm.qcow2" || { echo "the virtual machine's qcow2 differs from its raw disk" >&2; exit 1; }
  (cd "$OUT" && sha256sum "$NAME-vm.qcow2" > "$NAME-vm.qcow2.sha256")
  rm -f "$vm"
  log "virtual machine's disk: $(du -h "$OUT/$NAME-vm.qcow2" | cut -f1) ($VM_DISK)"
}

# A copy that can be reached over SSH on the owner's own network, to test on a real Pi (or in a
# VM): root logs in with the key in $TEST_SSH_KEY only (passwords are refused) and only from
# private network addresses; Avahi announces it as "Linux Mint ARM test on HOSTNAME", from the
# first-start setup on; the Pi's bootloader (EEPROM) is left as it is. Its SSH host key is kept
# next to it, so the first connection can be checked. Never released: it goes to $W/out-test.
make_test_image() {
  local key=$1 tout=$W/out-test test=$D/$NAME-TEST-ssh.img
  log "making the SSH test image"
  rm -rf "$tout" && mkdir -p "$tout"
  cp --sparse=always "$IMG" "$test"
  attach "$test"
  sudo mv "$MNT/etc/resolv.conf" "$MNT/etc/resolv.conf.image"
  sudo cp -L /etc/resolv.conf "$MNT/etc/resolv.conf"
  no_services on
  {
    in_image apt-get -q update
    in_image apt-get -y -q -o APT::Install-Recommends=false install openssh-server mesa-utils
    in_image apt-get clean
  } > "$W/logs/test-image.log" 2>&1 || { tail -20 "$W/logs/test-image.log"; exit 1; }
  no_services off
  sudo rm -f "$MNT"/var/lib/apt/lists/*_* "$MNT/etc/resolv.conf"
  sudo mv "$MNT/etc/resolv.conf.image" "$MNT/etc/resolv.conf"
  sudo install -d -m 700 "$MNT/root/.ssh"
  printf 'from="10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,fe80::/10,fd00::/8" %s\n' "$(cat "$key")" \
    | sudo tee "$MNT/root/.ssh/authorized_keys" > /dev/null
  sudo chmod 600 "$MNT/root/.ssh/authorized_keys"
  printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin prohibit-password\n' \
    | sudo tee "$MNT/etc/ssh/sshd_config.d/50-mint-arm-test.conf" > /dev/null
  sudo tee "$MNT/etc/avahi/services/mint-arm-test-ssh.service" > /dev/null <<'EOF'
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">Linux Mint ARM test on %h</name>
  <service><type>_ssh._tcp</type><port>22</port></service>
</service-group>
EOF
  # Avahi normally starts with the desktop; start it with the first-start setup too
  sudo mkdir -p "$MNT/etc/systemd/system/oem-config.target.wants"
  sudo ln -sf /usr/lib/systemd/system/avahi-daemon.service "$MNT/etc/systemd/system/oem-config.target.wants/"
  in_image systemctl mask rpi-eeprom-update.service 2> /dev/null
  cp "$MNT/etc/ssh/ssh_host_ed25519_key.pub" "$tout/ssh_host_ed25519_key.pub"
  TESTING=1 check_image
  leave_image
  log "compressing the test image"
  compress "$test" "$tout/$NAME-TEST-ssh.img.xz"
  rm -f "$test"
  log "test image: $(du -h "$tout/$NAME-TEST-ssh.img.xz" | cut -f1) (SSH host key $(ssh-keygen -lf "$tout/ssh_host_ed25519_key.pub" | cut -d' ' -f2))"
}

make_image
leave_image
log "compressing $NAME.img.xz"
# A 384 MiB window (64 MiB at -9) reaches the files that are alike but far apart in the image:
# about 60 MB less to download, for some ten minutes more here and 385 MB of memory to unpack it.
compress "$IMG" "$OUT/$NAME.img.xz" --lzma2=preset=9,dict=384MiB
log "image: $(du -h "$OUT/$NAME.img.xz" | cut -f1) compressed, $(du -h --apparent-size "$IMG" | cut -f1) written to a card"
make_vm_disk
if [ -n "${TEST_SSH_KEY:-}" ]; then make_test_image "$TEST_SSH_KEY"; fi
