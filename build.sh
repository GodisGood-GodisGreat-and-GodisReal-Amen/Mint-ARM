#!/bin/zsh
# Build Linux Mint ARM from scratch on an Apple-silicon Mac, with one command.
#
# usage: ./build.sh [--test-ssh] [--keep-vm] [WORK_DIR]
#
# Stage 00 starts an Ubuntu 24.04 arm64 build VM (QEMU with Apple's Hypervisor framework).
# Stages 10 to 35 run inside it: they rebuild Linux Mint's packages for arm64, assemble the system,
# make the disk image that starts on a Raspberry Pi and in virtual machines, and the live/install
# ISO for virtual machines. Stage 40 wraps the image, prepared for a VM, as a ready-to-run UTM
# virtual machine. The image, the VM, the ISO and the mint-arm-repo package (Mint's packages for
# arm64, for updating systems made from an earlier release) land in out/.
#
# --test-ssh also makes a test image that root can log in to over SSH with a key made here, in
# work/pi-test/: for testing on a real Raspberry Pi, never for a release.
# WORK_DIR (default: work/) keeps the build VM's disk, so running the command again after a
# failure resumes instead of starting over; delete it to start clean. --keep-vm leaves the build
# VM running at the end, for a look inside. About 45 minutes on an M4 Max; the build
# needs ~70 GB of disk. See docs/building.md.
emulate -L zsh
setopt err_exit pipe_fail no_unset

HERE=${0:A:h}
KEEP_VM=0 TEST_SSH=0
while [[ ${1:-} == --* ]]; do
  case $1 in
    --keep-vm) KEEP_VM=1 ;;
    --test-ssh) TEST_SSH=1 ;;
    *) print -ru2 -- "build.sh: unknown option $1"; exit 1 ;;
  esac
  shift
done
WORK=${${1:-$HERE/work}:a}
OUT=${OUT:-$HERE/out}
VM=$WORK/build-vm
PORT=${BUILD_SSH_PORT:-2299}
NAME=linuxmint-22.3-cinnamon-arm64-unofficial
STAGES=(10-packages 15-mintarm 20-rootfs 30-image 35-iso)
NEED_GB=70

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
if (( TEST_SSH )); then
  mkdir -p $WORK/pi-test
  [[ -f $WORK/pi-test/id_ed25519 ]] || ssh-keygen -q -t ed25519 -N '' -C mint-arm-pi-test -f $WORK/pi-test/id_ed25519
fi
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
(( TEST_SSH )) && vm 'cat > ~/pi-test.pub' < $WORK/pi-test/id_ed25519.pub

# The stages see the Mac's time zone (for their log times) and any of these settings set here.
tz=$(readlink /etc/localtime 2> /dev/null) tz=${tz#*zoneinfo/}
settings="TZ=${tz:-UTC}"
for name in JOBS PAR MINT_MIRROR UBUNTU_MIRROR SQUASHFS_COMP; do
  [[ -n ${(P)name:-} ]] && settings+=" $name=${(qq)${(P)name}}"
done
for stage in $STAGES; do
  stage_env=$settings
  [[ $stage == 30-image ]] && (( TEST_SSH )) && stage_env+=' TEST_SSH_KEY=$HOME/pi-test.pub'
  log "stage $stage"
  t0=$SECONDS
  vm "$stage_env bash ~/build/$stage.sh" < /dev/null 2>&1 | tee $WORK/logs/$stage.log \
    || die "stage $stage failed. Its output is in $WORK/logs/$stage.log, the detailed logs in the VM's /srv/mintarm/logs (--keep-vm keeps it running). Run ./build.sh again to resume."
  log "stage $stage done in $(took $t0)"
done

# FILE in the VM, with its .sha256 next to it, into DIR on the Mac; checked
copy_out() {
  local file=$1 dir=$2 name=${1:t}
  vm "cat $file" < /dev/null > $dir/$name.part
  vm "cat $file.sha256" < /dev/null > $dir/$name.sha256
  mv $dir/$name.part $dir/$name
  (cd $dir && shasum -a 256 -c $name.sha256 > /dev/null) || die "the copied $name does not match its checksum"
}
log "copying $NAME.img.xz, the virtual machine's disk and the ISO to $OUT"
# an earlier build's results, including files this build no longer makes
rm -f $OUT/linuxmint-22.3-cinnamon-arm64-*(N) $OUT/mint-arm-repo_*.deb(N)
copy_out /srv/mintarm/out/$NAME.img.xz $OUT
copy_out /srv/mintarm/out/$NAME-vm.qcow2 $OUT
copy_out /srv/mintarm/out/$NAME.iso $OUT
outputs=($OUT/$NAME.img.xz "$OUT/Linux Mint 22.3 ARM.utm" $OUT/$NAME.iso)
if (( TEST_SSH )); then
  log "copying the SSH test image to $WORK/pi-test"
  rm -f $WORK/pi-test/linuxmint-22.3-cinnamon-arm64-*(N)
  copy_out /srv/mintarm/out-test/$NAME-TEST-ssh.img.xz $WORK/pi-test
  # the test image's own SSH host key, so the first connection to it is checked
  print -r -- "* $(vm 'cut -d" " -f1,2 /srv/mintarm/out-test/ssh_host_ed25519_key.pub' < /dev/null)" > $WORK/pi-test/known_hosts
  outputs+=($WORK/pi-test/$NAME-TEST-ssh.img.xz)
fi
# The local archive as a package of its own: installing a newer one updates Mint's packages
# in a system made from an earlier release.
repo_deb=$(vm 'cd /srv/mintarm/mint-arm-repo && ls mint-arm-repo_*.deb' < /dev/null)
vm "cat /srv/mintarm/mint-arm-repo/$repo_deb" < /dev/null > $OUT/$repo_deb
outputs+=($OUT/$repo_deb)
stop_vm

log "stage 40-vm-image"
$HERE/build/40-vm-image.sh $OUT/$NAME-vm.qcow2 $OUT 2>&1 | tee $WORK/logs/40-vm-image.log

log "finished in $(took 0):"
du -sh $outputs
