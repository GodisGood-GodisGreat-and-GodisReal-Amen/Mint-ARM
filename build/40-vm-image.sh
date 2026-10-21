#!/bin/zsh
# Linux Mint ARM build, stage 40 (on the Mac): preinstall the ISO into a disk image with Mint's own
# installer in OEM mode, then wrap the disk as a ready-to-run UTM virtual machine.
# The first boot of the VM starts Mint's setup wizard (language, keyboard, time zone, your user).
#
# usage: 40-vm-image.sh ISO OUT_DIR
# needs: QEMU (Homebrew), bsdtar and cpio (both part of macOS)
emulate -L zsh
setopt err_exit pipe_fail

ISO=${1:?usage: 40-vm-image.sh ISO OUT_DIR}
OUT=${2:?usage: 40-vm-image.sh ISO OUT_DIR}
HERE=${0:A:h}
NAME="Linux Mint 22.3 ARM"
DISK_SIZE=64G
INSTALL_TIMEOUT=1800
QEMU=$(command -v qemu-system-aarch64) || { print -u2 "qemu-system-aarch64 not found (brew install qemu)"; exit 1 }
FIRMWARE=${QEMU:A:h:h}/share/qemu
WORK=$OUT/.vm-work
BUNDLE=$OUT/$NAME.utm

log() { print -r -- "[$(date +%H:%M:%S)] $*" }

rm -rf $WORK && mkdir -p $WORK
bsdtar -xf $ISO -C $WORK casper/vmlinuz casper/initrd.lz
chmod -R u+w $WORK/casper

# Hand the OEM answers to casper inside an extra initramfs archive (casper reads /preseed.cfg).
# An appended uncompressed cpio must start on a 4-byte boundary.
mkdir -p $WORK/seed && cp $HERE/utm-oem.seed $WORK/seed/preseed.cfg
(cd $WORK/seed && print preseed.cfg | cpio -o -H newc 2>/dev/null) > $WORK/preseed.cpio
pad=$(( (4 - $(stat -f %z $WORK/casper/initrd.lz) % 4) % 4 ))
{ cat $WORK/casper/initrd.lz; if (( pad )); then head -c $pad /dev/zero; fi; cat $WORK/preseed.cpio } > $WORK/initrd

qemu-img create -q -f qcow2 $WORK/disk.qcow2 $DISK_SIZE
cp $FIRMWARE/edk2-arm-vars.fd $WORK/vars.fd

# discard=unmap lets the installer's final fstrim (see utm-oem.seed) hand freed blocks back,
# so they are not packed into the VM.
log "installing (Ubiquity, OEM mode, unattended)"
$QEMU -name mint-arm-oem-install -machine virt,highmem=on -accel hvf -cpu host -smp 6 -m 8G \
  -drive if=pflash,format=raw,readonly=on,file=$FIRMWARE/edk2-aarch64-code.fd \
  -drive if=pflash,format=raw,file=$WORK/vars.fd \
  -device qemu-xhci -device usb-kbd -device usb-tablet -device virtio-gpu-pci \
  -drive if=none,id=hd0,file=$WORK/disk.qcow2,format=qcow2,discard=unmap,cache=writeback \
  -device virtio-blk-pci,drive=hd0 \
  -drive if=none,id=cd0,file=$ISO,format=raw,media=cdrom,readonly=on -device usb-storage,drive=cd0,removable=on \
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0 -device virtio-rng-pci \
  -display none -monitor none -serial file:$WORK/install-serial.log \
  -kernel $WORK/casper/vmlinuz -initrd $WORK/initrd \
  -append "boot=casper automatic-ubiquity noprompt oem-config/enable=true username=mint hostname=mint quiet splash --" &
qemu=$!
for (( t = 0; t < INSTALL_TIMEOUT; t += 5 )); do
  kill -0 $qemu 2>/dev/null || break
  sleep 5
done
if kill -0 $qemu 2>/dev/null; then
  kill $qemu
  print -u2 "install did not finish within ${INSTALL_TIMEOUT}s (see $WORK/install-serial.log)"
  exit 1
fi
wait $qemu || true
used=$(qemu-img info --output=json $WORK/disk.qcow2 | python3 -c 'import json,sys; print(json.load(sys.stdin)["actual-size"])')
(( used > 3000000000 )) || { print -u2 "install looks incomplete: only $used bytes written"; exit 1 }

# zstd clusters are smaller than zlib ones and faster to read back while the VM runs.
log "packing the UTM virtual machine"
rm -rf $BUNDLE && mkdir -p $BUNDLE/Data
disk_id=$(uuidgen)
qemu-img convert -c -O qcow2 -o compression_type=zstd $WORK/disk.qcow2 $BUNDLE/Data/$disk_id.qcow2
qemu-img check -q $BUNDLE/Data/$disk_id.qcow2
mac=$(printf '52:54:00:%02X:%02X:%02X' $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)))
sed -e "s/@NAME@/$NAME/" -e "s/@VM_UUID@/$(uuidgen)/" -e "s/@DISK_ID@/$disk_id/" \
    -e "s/@CD_ID@/$(uuidgen)/" -e "s/@MAC@/$mac/" \
    $HERE/utm-config.plist.in > $BUNDLE/config.plist
plutil -lint $BUNDLE/config.plist > /dev/null
rm -rf $WORK
log "done: $BUNDLE ($(du -sh $BUNDLE | cut -f1))"
