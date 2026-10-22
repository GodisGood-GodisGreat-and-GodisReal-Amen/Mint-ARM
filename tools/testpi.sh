#!/bin/zsh
# Start the Linux Mint ARM image on this Mac the way a Raspberry Pi starts it, headless, for
# testing: QEMU with Apple's Hypervisor framework runs the image's own Raspberry Pi kernel and
# initrd from its boot partition (they also run on QEMU's "virt" machine), on a copy-on-write
# overlay larger than the image, so the first start grows the system as it does on a bigger
# card. The image would take QEMU for a virtual machine; mint-arm.platform=pi (in APPEND) makes
# its first start act as on a Pi. What only a real Pi has (its firmware and config.txt, its GPU,
# Wi-Fi and Bluetooth) is for a test on a Pi; see docs/building.md. Drive it with qmp.py
# (screenshots, keys, clicks), qga.py (with QGA_PORT), or pitest.sh 127.0.0.1:SSH_PORT for the
# SSH test image.
#
# usage: testpi.sh NAME IMAGE [-- extra QEMU arguments]
#   IMAGE  the .img.xz (decompressed once, into the test's folder) or a raw .img
# env:  QMP_PORT (4460)  QMP on 127.0.0.1, for qmp.py
#       SSH_PORT (2240)  forwarded to the guest's port 22
#       QGA_PORT         the guest agent on 127.0.0.1, for qga.py (none when unset)
#       APPEND           added to the kernel command line, e.g. "mint-arm.platform=pi"
#       SMP (4) MEM (4G) RES (1920x1080) CARD (32G: the overlay's size, the "card")
# The image, the overlay, the boot files and the serial log are kept in work/testpis/NAME;
# delete the overlay to start again from the image.
emulate -L zsh
setopt err_exit pipe_fail

NAME=${1:?usage: testpi.sh NAME IMAGE [-- QEMU arguments]}
IMAGE=${2:?usage: testpi.sh NAME IMAGE [-- QEMU arguments]}
shift 2
[[ ${1:-} == -- ]] && shift
HERE=${0:A:h}
QEMU=$(command -v qemu-system-aarch64) || { print -u2 "qemu-system-aarch64 not found (brew install qemu)"; exit 1 }
DIR=${TESTPI_DIR:-${HERE:h}/work/testpis}/$NAME
RES=${RES:-1920x1080}
mkdir -p $DIR

raw=${IMAGE:A}
if [[ $IMAGE == *.xz ]]; then
  raw=$DIR/image.img
  if [[ ! -f $raw || $IMAGE -nt $raw ]]; then
    print "decompressing ${IMAGE:t}"
    rm -f $DIR/overlay.qcow2
    xz -dc $IMAGE > $raw.part && mv $raw.part $raw
  fi
fi
[[ -f $DIR/overlay.qcow2 ]] || qemu-img create -q -f qcow2 -b $raw -F raw $DIR/overlay.qcow2 ${CARD:-32G}
python3 $HERE/pi-boot-files.py $raw $DIR/boot

args=(
  -name $NAME -machine virt,highmem=on -accel hvf -cpu host -smp ${SMP:-4} -m ${MEM:-4G}
  -kernel $DIR/boot/vmlinuz -initrd $DIR/boot/initrd.img
  -append "$(cat $DIR/boot/cmdline.txt) console=ttyAMA0 console=tty1 ${APPEND:-}"
  -device qemu-xhci,id=xhci -device usb-kbd -device usb-tablet
  -device virtio-gpu-pci,xres=${RES%x*},yres=${RES#*x}
  -drive if=none,id=hd0,file=$DIR/overlay.qcow2,format=qcow2,discard=unmap,cache=writeback -device virtio-blk-pci,drive=hd0
  -netdev user,id=n0,hostfwd=tcp:127.0.0.1:${SSH_PORT:-2240}-:22 -device virtio-net-pci,netdev=n0
  -device virtio-rng-pci
  -display none -monitor none -serial file:$DIR/serial.log
  -qmp tcp:127.0.0.1:${QMP_PORT:-4460},server,wait=off
)
if [[ -n ${QGA_PORT:-} ]]; then
  args+=(-device virtio-serial-pci
         -chardev socket,id=qga0,host=127.0.0.1,port=$QGA_PORT,server=on,wait=off
         -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0)
fi
exec $QEMU $args "$@"
