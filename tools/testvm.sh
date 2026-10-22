#!/bin/zsh
# A headless test VM with the virtual hardware of the UTM VM (QEMU backend): Apple's Hypervisor
# framework, a USB CD drive, keyboard and tablet, virtio disk, network and GPU, Intel HD Audio.
# Nothing is shown on screen; drive it with qmp.py (screenshots, keys, clicks) and qga.py
# (commands and files through the QEMU guest agent).
#
# usage: testvm.sh NAME DISK [ISO] [-- extra QEMU arguments]
#   DISK  a qcow2 disk, such as the one inside the .utm bundle (add "-- -snapshot" to leave it untouched)
#   ISO   boot from this ISO, with DISK attached
# env:  QMP_PORT (4450)       QMP on 127.0.0.1, for qmp.py
#       QGA_PORT              the guest agent on 127.0.0.1, for qga.py (none when unset)
#       SSH_PORT              forwards 127.0.0.1:SSH_PORT to the guest's port 22 (none when unset)
#       SMP (6) MEM (8G) RES (1920x1080)
#       KERNEL INITRD APPEND  boot a kernel directly instead of going through the firmware
# The VM's UEFI variables and serial log are kept in work/testvms/NAME.
emulate -L zsh
setopt err_exit

NAME=${1:?usage: testvm.sh NAME DISK [ISO] [-- QEMU arguments]}
DISK=${2:?usage: testvm.sh NAME DISK [ISO] [-- QEMU arguments]}
shift 2
ISO=
if [[ $# -gt 0 && $1 != -- ]]; then ISO=$1; shift; fi
[[ ${1:-} == -- ]] && shift
QEMU=$(command -v qemu-system-aarch64) || { print -u2 "qemu-system-aarch64 not found (brew install qemu)"; exit 1 }
FIRMWARE=${QEMU:A:h:h}/share/qemu
DIR=${TESTVM_DIR:-${0:A:h:h}/work/testvms}/$NAME
RES=${RES:-1920x1080}
mkdir -p $DIR
[[ -f $DIR/vars.fd ]] || cp $FIRMWARE/edk2-arm-vars.fd $DIR/vars.fd

args=(
  -name $NAME -machine virt,highmem=on -accel hvf -cpu host -smp ${SMP:-6} -m ${MEM:-8G}
  -drive if=pflash,format=raw,readonly=on,file=$FIRMWARE/edk2-aarch64-code.fd
  -drive if=pflash,format=raw,file=$DIR/vars.fd
  -device qemu-xhci,id=xhci -device usb-kbd -device usb-tablet
  -device virtio-gpu-pci,xres=${RES%x*},yres=${RES#*x}
  -drive if=none,id=hd0,file=$DISK,format=qcow2,discard=unmap,cache=writeback -device virtio-blk-pci,drive=hd0,bootindex=1
  -netdev user,id=n0${SSH_PORT:+,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22} -device virtio-net-pci,netdev=n0
  -audiodev none,id=snd0 -device intel-hda -device hda-duplex,audiodev=snd0
  -device virtio-rng-pci
  -display none -monitor none -serial file:$DIR/serial.log
  -qmp tcp:127.0.0.1:${QMP_PORT:-4450},server,wait=off
)
if [[ -n $ISO ]]; then
  args+=(-drive if=none,id=cd0,file=$ISO,format=raw,media=cdrom,readonly=on
         -device usb-storage,drive=cd0,removable=on,bootindex=0)
fi
if [[ -n ${QGA_PORT:-} ]]; then
  args+=(-device virtio-serial-pci
         -chardev socket,id=qga0,host=127.0.0.1,port=$QGA_PORT,server=on,wait=off
         -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0)
fi
if [[ -n ${KERNEL:-} ]]; then
  args+=(-kernel $KERNEL -initrd ${INITRD:?INITRD is needed with KERNEL} -append ${APPEND:-})
fi
exec $QEMU $args "$@"
