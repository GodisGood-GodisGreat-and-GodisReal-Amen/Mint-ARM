#!/bin/zsh
# Linux Mint ARM build, stage 00 (on the Mac): start the Ubuntu 24.04 arm64 build VM.
# QEMU with Apple's Hypervisor framework runs it at native speed; stages 10 to 30 run inside it.
# ../build.sh runs every stage for you; this script is for running them by hand.
#
# usage: 00-build-vm.sh DIR   (DIR holds the VM's disk: about 40 GB once a build has run)
# then:  ssh -i DIR/id_build -p 2299 builder@127.0.0.1
# env:   BUILD_CPUS     virtual CPUs (default: the Mac's performance cores)
#        BUILD_MEM      memory (default: half the Mac's, between 6 and 32 GB), e.g. 16G
#        BUILD_SSH_PORT the Mac's port forwarded to the VM's SSH (default 2299)
emulate -L zsh
setopt err_exit pipe_fail

DIR=${1:?usage: 00-build-vm.sh DIR}
IMAGE_URL=https://cloud-images.ubuntu.com/noble/current
IMAGE=noble-server-cloudimg-arm64.img
QEMU=$(command -v qemu-system-aarch64) || { print -u2 "qemu-system-aarch64 not found (brew install qemu)"; exit 1 }
FIRMWARE=${QEMU:A:h:h}/share/qemu
[[ -f $FIRMWARE/edk2-aarch64-code.fd ]] || { print -u2 "no UEFI firmware in $FIRMWARE"; exit 1 }
ram_gb=$(( $(sysctl -n hw.memsize) / 1073741824 ))
CPUS=${BUILD_CPUS:-$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || sysctl -n hw.physicalcpu)}
MEM=${BUILD_MEM:-$(( ram_gb / 2 > 32 ? 32 : (ram_gb / 2 < 6 ? 6 : ram_gb / 2) ))G}
PORT=${BUILD_SSH_PORT:-2299}
mkdir -p $DIR && cd $DIR

if [[ ! -f noble-arm64.img ]]; then
  curl -fsS -o noble-arm64.img.part $IMAGE_URL/$IMAGE
  curl -fsS -o SHA256SUMS $IMAGE_URL/SHA256SUMS
  [[ $(shasum -a 256 noble-arm64.img.part | cut -d' ' -f1) == $(awk -v f="*$IMAGE" '$2 == f {print $1}' SHA256SUMS) ]] \
    || { print -u2 "cloud image checksum mismatch"; exit 1 }
  mv noble-arm64.img.part noble-arm64.img
fi
[[ -f id_build ]] || ssh-keygen -q -t ed25519 -N '' -C mintarm-build -f id_build
if [[ ! -f seed.iso ]]; then
  mkdir -p seed
  print -r -- "instance-id: mintarm-build-1
local-hostname: mintarm-build" > seed/meta-data
  # Automatic apt runs would hold the package lock while the build installs its tools.
  print -r -- "#cloud-config
users:
  - name: builder
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - $(<id_build.pub)
ssh_pwauth: false
growpart: {mode: auto, devices: ['/']}
runcmd:
  - [systemctl, disable, --now, apt-daily.timer, apt-daily-upgrade.timer, unattended-upgrades.service]" > seed/user-data
  hdiutil makehybrid -quiet -o seed.iso seed -iso -joliet -default-volume-name cidata
fi
[[ -f build.qcow2 ]] || qemu-img create -q -f qcow2 -b noble-arm64.img -F qcow2 build.qcow2 160G
[[ -f vars.fd ]] || cp $FIRMWARE/edk2-arm-vars.fd vars.fd

exec $QEMU \
  -name mintarm-build -machine virt,highmem=on -accel hvf -cpu host -smp $CPUS -m $MEM \
  -drive if=pflash,format=raw,readonly=on,file=$FIRMWARE/edk2-aarch64-code.fd \
  -drive if=pflash,format=raw,file=vars.fd \
  -drive if=none,id=d0,file=build.qcow2,format=qcow2,discard=unmap,cache=writeback -device virtio-blk-pci,drive=d0 \
  -drive if=none,id=s0,file=seed.iso,format=raw,readonly=on -device virtio-blk-pci,drive=s0 \
  -netdev user,id=n0,hostfwd=tcp:127.0.0.1:$PORT-:22 -device virtio-net-pci,netdev=n0 \
  -device virtio-rng-pci -display none -monitor none -serial file:serial.log
