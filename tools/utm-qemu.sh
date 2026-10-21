#!/bin/zsh
# Run a VM headlessly on UTM's own QEMU, display included: with GPU=1 the display is UTM's
# "GPU Supported" one (virtio-gpu-gl-pci through virglrenderer and ANGLE onto Metal), with GPU=0
# the standard one. This tests what UTM runs, without UTM's window. utm-qemu.c is compiled and
# ad-hoc signed with the hypervisor entitlement on first use, into work/utm-qemu/.
#
# usage: utm-qemu.sh NAME DISK [-- extra QEMU arguments]   (add "-- -snapshot" to leave DISK untouched)
# env:   GPU (1)  QMP_PORT (4450)  QGA_PORT (none)  SMP (6)  MEM (8G)  RES (1920x1080)
#        UTM (/Applications/UTM.app)
# The display goes to a SPICE socket that nothing needs to read. QEMU's screendump stays black
# while SPICE draws with OpenGL, so take screenshots inside the guest (gnome-screenshot).
emulate -L zsh
setopt err_exit

NAME=${1:?usage: utm-qemu.sh NAME DISK [-- QEMU arguments]}
DISK=${2:?usage: utm-qemu.sh NAME DISK [-- QEMU arguments]}
shift 2
[[ ${1:-} == -- ]] && shift
UTM=${UTM:-/Applications/UTM.app}
FRAMEWORK=$UTM/Contents/Frameworks/qemu-aarch64-softmmu.framework/qemu-aarch64-softmmu
[[ -f $FRAMEWORK ]] || { print -u2 "UTM's QEMU not found in $UTM"; exit 1 }
DIR=${0:A:h:h}/work/utm-qemu
BIN=$DIR/utm-qemu
RES=${RES:-1920x1080}
mkdir -p $DIR/$NAME

if [[ ! -x $BIN || ${0:A:h}/utm-qemu.c -nt $BIN ]]; then
  clang -O2 -Wall -o $BIN ${0:A:h}/utm-qemu.c -Wl,-rpath,$UTM/Contents/Frameworks
  print -r -- '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.hypervisor</key><true/></dict></plist>' > $DIR/entitlements.plist
  codesign -s - -f --entitlements $DIR/entitlements.plist $BIN
fi
if [[ ! -f $DIR/$NAME/vars.fd ]]; then
  # UTM ships the variable store unpadded; the virt machine's flash wants exactly 64 MiB
  cp $UTM/Contents/Resources/qemu/edk2-arm-vars.fd $DIR/$NAME/vars.fd
  dd if=/dev/null of=$DIR/$NAME/vars.fd bs=1048576 seek=64 2> /dev/null
fi

if [[ ${GPU:-1} == 1 ]]; then gpu=virtio-gpu-gl-pci gl=on; else gpu=virtio-gpu-pci gl=off; fi
args=(
  -L $UTM/Contents/Resources/qemu
  -name $NAME -machine virt,highmem=on -accel hvf -cpu host -smp ${SMP:-6} -m ${MEM:-8G}
  -drive if=pflash,format=raw,readonly=on,file=$UTM/Contents/Resources/qemu/edk2-aarch64-code.fd
  -drive if=pflash,format=raw,file=$DIR/$NAME/vars.fd
  -device qemu-xhci,id=xhci -device usb-kbd -device usb-tablet
  -device $gpu,xres=${RES%x*},yres=${RES#*x}
  -drive if=none,id=hd0,file=${DISK:A},format=qcow2,discard=unmap,cache=writeback -device virtio-blk-pci,drive=hd0
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0
  -audiodev none,id=snd0 -device intel-hda -device hda-duplex,audiodev=snd0
  -device virtio-rng-pci
  -device virtio-serial-pci
  -chardev spicevmc,id=vdagent,name=vdagent -device virtserialport,chardev=vdagent,name=com.redhat.spice.0
  -display none -monitor none -serial file:$DIR/$NAME/serial.log
  -spice unix=on,addr=$NAME.sock,disable-ticketing=on,gl=$gl
  -qmp tcp:127.0.0.1:${QMP_PORT:-4450},server,wait=off
)
if [[ -n ${QGA_PORT:-} ]]; then
  args+=(-chardev socket,id=qga0,host=127.0.0.1,port=$QGA_PORT,server=on,wait=off
         -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0)
fi
# The SPICE socket path is relative: a Unix socket path must stay under 104 bytes.
cd $DIR/$NAME
export ANGLE_DEFAULT_PLATFORM=metal
exec $BIN $FRAMEWORK $args "$@"
