#!/bin/zsh
# Linux Mint ARM build, stage 40 (on the Mac): wrap the virtual machine's disk that 30-image.sh
# prepared (the image on a 64 GB disk, its first start in a VM already done) as a ready-to-run UTM
# virtual machine. The VM's first start runs Mint's setup wizard (language, keyboard, time zone,
# your user).
#
# usage: 40-vm-image.sh DISK.qcow2 OUT_DIR   (the disk moves into the bundle)
emulate -L zsh
setopt err_exit pipe_fail

DISK=${1:?usage: 40-vm-image.sh DISK.qcow2 OUT_DIR}
OUT=${2:?usage: 40-vm-image.sh DISK.qcow2 OUT_DIR}
HERE=${0:A:h}
NAME="Linux Mint 22.3 ARM"
BUNDLE=$OUT/$NAME.utm

log() { print -r -- "[$(date +%H:%M:%S)] $*" }

command -v qemu-img > /dev/null || { print -u2 "qemu-img not found (brew install qemu)"; exit 1 }
qemu-img check -q $DISK
rm -rf $BUNDLE && mkdir -p $BUNDLE/Data
disk_id=$(uuidgen)
mv $DISK $BUNDLE/Data/$disk_id.qcow2
rm -f $DISK.sha256
mac=$(printf '52:54:00:%02X:%02X:%02X' $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)))
sed -e "s/@NAME@/$NAME/" -e "s/@VM_UUID@/$(uuidgen)/" -e "s/@DISK_ID@/$disk_id/" \
    -e "s/@CD_ID@/$(uuidgen)/" -e "s/@MAC@/$mac/" \
    $HERE/utm-config.plist.in > $BUNDLE/config.plist
plutil -lint $BUNDLE/config.plist > /dev/null
log "done: $BUNDLE ($(du -sh $BUNDLE | cut -f1))"
