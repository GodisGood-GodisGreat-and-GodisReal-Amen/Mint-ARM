#!/bin/zsh
# Build Linux Mint ARM from scratch on an Apple-silicon Mac, with one command.
#
# usage: ./build.sh [--keep-vm] [WORK_DIR]
#
# Stage 00 starts an Ubuntu 24.04 arm64 build VM (QEMU with Apple's Hypervisor framework).
# Stages 10 to 30 run inside it: they rebuild Linux Mint's packages for arm64, assemble the
# system and pack the live ISO. Stage 40 preinstalls that ISO into a ready-to-run UTM virtual
# machine with Mint's own installer. The ISO, the VM and the mint-arm-repo package (Mint's
# packages for arm64, for updating systems made from an earlier release) land in out/.
#
# WORK_DIR (default: work/) keeps the build VM's disk, so running the command again after a
# failure resumes instead of starting over; delete it to start clean. --keep-vm leaves the build
# VM running at the end, for a look inside. About 35 minutes on an M4 Max; needs ~50 GB of disk.
# See docs/building.md.
emulate -L zsh
setopt err_exit pipe_fail no_unset

HERE=${0:A:h}
KEEP_VM=0
if [[ ${1:-} == --keep-vm ]]; then KEEP_VM=1; shift; fi
WORK=${${1:-$HERE/work}:a}
OUT=${OUT:-$HERE/out}
VM=$WORK/build-vm
PORT=${BUILD_SSH_PORT:-2299}
STAGES=(10-packages 15-mintarm 20-rootfs 30-iso)
NEED_GB=50

log() { print -r -- "[$(date +%H:%M:%S)] $*" }
took() { (( SECONDS - $1 < 90 )) && print -r -- "$(( SECONDS - $1 )) s" || print -r -- "$(( (SECONDS - $1 + 30) / 60 )) min" }
die() { print -ru2 -- "build.sh: $*"; exit 1 }
vm() {
  ssh -q -i $VM/id_build -p $PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o LogLevel=ERROR -o ConnectTimeout=5 -o ServerAliveInterval=30 builder@127.0.0.1 "$@"
}

[[ $(uname -sm) == "Darwin arm64" ]] || die "this needs a Mac with Apple silicon"
for tool in qemu-system-aarch64 qemu-img; do
  command -v $tool > /dev/null || die "$tool not found: install QEMU first (brew install qemu)"
done
mkdir -p $WORK/logs $OUT
caffeinate -i -w $$ &   # no idle sleep until the build ends

started=0 qemu_pid=
stop_vm() {
  (( started )) || return 0
  started=0
  if (( KEEP_VM )); then
    log "the build VM keeps running: ssh -i $VM/id_build -p $PORT builder@127.0.0.1"
    return 0
  fi
  log "stopping the build VM"
  vm 'sudo systemctl poweroff' < /dev/null 2> /dev/null || true
  for (( i = 0; i < 60; i++ )); do
    kill -0 $qemu_pid 2> /dev/null || return 0
    sleep 2
  done
  kill $qemu_pid 2> /dev/null || true
}
trap stop_vm EXIT
trap 'exit 130' INT TERM

if [[ -f $VM/id_build ]] && vm true < /dev/null 2> /dev/null; then
  log "using the build VM that is already running on port $PORT"
  qemu_pid=$(pgrep -f -- '-name mintarm-build' | head -1) started=1
else
  nc -z 127.0.0.1 $PORT 2> /dev/null && die "port $PORT is taken by another program: choose another with BUILD_SSH_PORT=..."
  if [[ ! -f $VM/build.qcow2 ]]; then
    free_gb=$(( $(df -k $WORK | awk 'NR == 2 {print $4}') / 1048576 ))
    (( free_gb >= NEED_GB )) || die "the build needs about $NEED_GB GB free in $WORK ($free_gb GB available)"
  fi
  [[ -f $VM/noble-arm64.img ]] || log "downloading Ubuntu 24.04's arm64 cloud image (600 MB)"
  $HERE/build/00-build-vm.sh $VM > $WORK/logs/00-build-vm.log 2>&1 &
  qemu_pid=$! started=1
  # 00-build-vm.sh creates vars.fd just before it starts QEMU
  while [[ ! -f $VM/vars.fd ]]; do
    kill -0 $qemu_pid 2> /dev/null || die "the build VM did not start: see $WORK/logs/00-build-vm.log"
    sleep 2
  done
  log "starting the build VM"
  for (( i = 0; ; i++ )); do
    vm true < /dev/null 2> /dev/null && break
    kill -0 $qemu_pid 2> /dev/null || die "the build VM stopped: see $WORK/logs/00-build-vm.log and $VM/serial.log"
    (( i < 300 )) || die "the build VM did not answer on port $PORT within 10 minutes (see $VM/serial.log)"
    sleep 2
  done
fi
# first boot: let cloud-init finish and any automatic apt run release the package lock
vm 'cloud-init status --wait > /dev/null 2>&1
    while sudo fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock > /dev/null 2>&1; do sleep 3; done' < /dev/null || true

log "copying build/ into the VM"
COPYFILE_DISABLE=1 bsdtar --no-mac-metadata --format ustar -C $HERE -cf - build \
  | vm 'rm -rf ~/build && tar -xf - --no-same-owner'

# The stages see the Mac's time zone (for their log times) and any of these settings set here.
tz=$(readlink /etc/localtime 2> /dev/null) tz=${tz#*zoneinfo/}
settings="TZ=${tz:-UTC}"
for name in JOBS PAR MINT_MIRROR UBUNTU_MIRROR SQUASHFS_COMP; do
  [[ -n ${(P)name:-} ]] && settings+=" $name=${(qq)${(P)name}}"
done
for stage in $STAGES; do
  log "stage $stage"
  t0=$SECONDS
  vm "$settings bash ~/build/$stage.sh" < /dev/null 2>&1 | tee $WORK/logs/$stage.log \
    || die "stage $stage failed. Its output is in $WORK/logs/$stage.log, the detailed logs in the VM's /srv/mintarm/logs (--keep-vm keeps it running). Run ./build.sh again to resume."
  log "stage $stage done in $(took $t0)"
done

iso=$(vm 'cd /srv/mintarm/out && ls -t *.iso | head -1' < /dev/null)
log "copying $iso to $OUT"
vm "cat /srv/mintarm/out/$iso" < /dev/null > $OUT/$iso.part
vm "cat /srv/mintarm/out/$iso.sha256" < /dev/null > $OUT/$iso.sha256
mv $OUT/$iso.part $OUT/$iso
(cd $OUT && shasum -a 256 -c $iso.sha256 > /dev/null) || die "the copied ISO does not match its checksum"
# The local archive as a package of its own: installing a newer one updates Mint's packages
# in a system made from an earlier release.
repo_deb=$(vm 'cd /srv/mintarm/mint-arm-repo && ls mint-arm-repo_*.deb' < /dev/null)
vm "cat /srv/mintarm/mint-arm-repo/$repo_deb" < /dev/null > $OUT/$repo_deb
stop_vm

log "stage 40-vm-image"
$HERE/build/40-vm-image.sh $OUT/$iso $OUT 2>&1 | tee $WORK/logs/40-vm-image.log

log "finished in $(took 0):"
du -sh $OUT/$iso "$OUT/Linux Mint 22.3 ARM.utm" $OUT/$repo_deb
