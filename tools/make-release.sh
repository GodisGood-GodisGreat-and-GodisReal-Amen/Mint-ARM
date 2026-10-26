#!/bin/zsh
# Turn a finished build (out/) into release files, in out/release/:
#   linuxmint-22.3-cinnamon-arm64-unofficial.img.xz    the image: a Raspberry Pi's card or a VM's disk
#   linuxmint-22.3-cinnamon-arm64-unofficial-utm.zip   the ready-made UTM virtual machine
#   linuxmint-22.3-cinnamon-arm64-unofficial.iso       the live/install ISO for virtual machines
#   mint-arm-repo_VERSION_all.deb                      Mint's packages for arm64, to update a
#                                                      system made from an earlier release
#   linuxmint-22.3-arm64-sources.tar                   Linux Mint's source packages for everything
#                                                      compiled or patched for arm64, with the patches
#   source-packages.tsv                                every source package in the image and the
#                                                      ISO, its version, and where its source lives
#   SHA256SUMS
# and, in the repository, imager/os_list.json: Raspberry Pi Imager's entry for this release's image
# (its URL, sizes and SHA-256s), to commit along with the release.
# The source list comes from the image itself: it starts headlessly in QEMU as testpi.sh starts it,
# on a throwaway overlay, with its first start held back so that both its halves are still there,
# and with the ISO attached as a read-only disk; it lists what the image, the ISO's live system and
# the ISO's package pool hold, and downloads Mint's sources with apt, which checks them against
# Linux Mint's signed index. The UTM VM's disk is that image with one half removed. A test image
# (with SSH, from ./build.sh --test-ssh) is refused.
#
# usage: tools/make-release.sh [OUT_DIR]
emulate -L zsh
setopt err_exit pipe_fail

HERE=${0:A:h}
ROOT=${HERE:h}
OUT=${${1:-$ROOT/out}:a}
REL=$OUT/release
QGA=4470 QMP=4471
VERSION=$(awk '/^## / {print $2; exit}' $ROOT/CHANGELOG.md)
REPO_URL=https://github.com/GodisGood-GodisGreat-and-GodisReal-Amen/Mint-ARM
BUNDLE="Linux Mint 22.3 ARM.utm"
IMAGE=linuxmint-22.3-cinnamon-arm64-unofficial.img.xz
ISO=linuxmint-22.3-cinnamon-arm64-unofficial.iso
SOURCES=linuxmint-22.3-arm64-sources
RELEASE_DATE=$(awk '/^## / {print $4; exit}' $ROOT/CHANGELOG.md)

log() { print -r -- "[$(date +%H:%M:%S)] $*" }
disk=($OUT/$BUNDLE/Data/*.qcow2(N))
[[ -f $OUT/$IMAGE && -f $OUT/$ISO && $#disk -gt 0 ]] || { print -u2 "no image, ISO or VM in $OUT: run ./build.sh first"; exit 1 }
# the documents a release points to carry no placeholder for a measurement or a date
if grep -rqE 'TODO-[A-Z]' $ROOT/README.md $ROOT/CHANGELOG.md $ROOT/CONTRIBUTING.md $ROOT/docs; then
  print -u2 "placeholders are left in the documents:"
  grep -rnoE 'TODO-[A-Z0-9-]+' $ROOT/README.md $ROOT/CHANGELOG.md $ROOT/CONTRIBUTING.md $ROOT/docs | sed "s|^$ROOT/|  |" >&2
  exit 1
fi
rm -rf $REL && mkdir -p $REL/.stage/$SOURCES

log "starting the image (its first start held back), on a throwaway overlay"
TESTPI_DIR=$REL/.stage QGA_PORT=$QGA QMP_PORT=$QMP SSH_PORT=4472 SMP=4 MEM=6G CARD=16G \
  APPEND="mint-arm.first-start=no systemd.unit=multi-user.target" \
  $HERE/testpi.sh vm $OUT/$IMAGE -- -drive if=none,id=iso0,file=$OUT/$ISO,format=raw,readonly=on \
  -device virtio-blk-pci,drive=iso0 > $REL/.stage/vm.log 2>&1 &
vm=$!
trap '$HERE/qmp.py $QMP cmd "{\"name\": \"quit\"}" > /dev/null 2>&1 || kill $vm 2> /dev/null || true' EXIT
$HERE/qga.py $QGA ping 600
$HERE/qga.py $QGA put $HERE/source-manifest.py /tmp/source-manifest.py

log "listing the source packages"
$HERE/qga.py $QGA run '
  # the image of a release has no SSH server and no keys (a --test-ssh image has both)
  if dpkg-query -W -f="\${db:Status-Abbrev}" openssh-server 2> /dev/null | grep -q "^ii" || [ -e /root/.ssh/authorized_keys ]; then
    echo "this is a test image (it has SSH access): build the release without --test-ssh"; exit 1
  fi
  nm-online -q --timeout=120   # the guest agent answers before the network is up
  for try in 1 2 3; do
    apt-get update -q > /tmp/apt-update.log 2>&1
    ls /var/lib/apt/lists/*ports.ubuntu.com*_noble_main_binary-arm64_Packages* > /dev/null 2>&1 \
      && ! grep -q "Failed to fetch http" /tmp/apt-update.log && break
    sleep 10
  done
  ls /var/lib/apt/lists/*ports.ubuntu.com*_noble_main_binary-arm64_Packages* > /dev/null || { tail -5 /tmp/apt-update.log; exit 1; }
  # the ISO: its live system (the squashfs) and the pool of packages that its installer can add
  iso=$(blkid -t TYPE=iso9660 -o device | head -1)
  [ -n "$iso" ] || { echo "the ISO is not attached"; exit 1; }
  mkdir -p /mnt/iso /mnt/live
  mount -o ro "$iso" /mnt/iso && mount -o ro,loop /mnt/iso/casper/filesystem.squashfs /mnt/live \
    || { echo "cannot mount the ISO or its live system"; exit 1; }
  python3 /tmp/source-manifest.py --status /var/lib/dpkg --status /mnt/live/var/lib/dpkg \
    --debs "/usr/share/mint-arm/repo/**/*.deb" --debs "/mnt/iso/pool/**/*.deb" > /tmp/source-packages.tsv
  python3 /tmp/source-manifest.py --rebuilt /usr/share/mint-arm/repo > /tmp/rebuilt.txt
  echo "$(wc -l < /tmp/source-packages.tsv) source packages, $(wc -l < /tmp/rebuilt.txt) rebuilt or patched"' 900

log "downloading Linux Mint's sources for the rebuilt packages"
$HERE/qga.py $QGA run '
  set -e
  echo "deb-src http://packages.linuxmint.com zena main upstream import backport" > /etc/apt/sources.list.d/mint-src.list
  apt-get update -q -o Dir::Etc::SourceList=/etc/apt/sources.list.d/mint-src.list -o Dir::Etc::SourceParts=- \
    -o APT::Get::List-Cleanup=0 > /dev/null
  rm -rf /tmp/src && mkdir /tmp/src && chown _apt /tmp/src && cd /tmp/src   # apt downloads as _apt
  while read -r spec; do apt-get source --download-only --only-source -q "$spec" > /dev/null; done < /tmp/rebuilt.txt
  tar -cf /tmp/sources.tar --owner=0 --group=0 --numeric-owner *
  echo "$(ls *.dsc | wc -l) source packages, $(du -sh . | cut -f1)"' 1800
$HERE/qga.py $QGA get /tmp/source-packages.tsv $REL/source-packages.tsv
$HERE/qga.py $QGA get /tmp/sources.tar $REL/.stage/sources.tar
$HERE/qmp.py $QMP cmd '{"name": "quit"}' > /dev/null
wait $vm || true
trap - EXIT

log "packing $SOURCES.tar"
tar -xf $REL/.stage/sources.tar -C $REL/.stage/$SOURCES
cp $ROOT/build/patches/*.patch $REL/.stage/$SOURCES/
cat > $REL/.stage/$SOURCES/README.txt <<EOF
Linux Mint ARM $VERSION: the source code of the Linux Mint packages built for arm64

This archive holds the Debian source packages (each .dsc and the files it lists) that the
Linux Mint ARM build downloaded from packages.linuxmint.com and compiled for arm64, exactly as
they went into the image, the UTM virtual machine made from it, and the ISO. mintsources and
mintupdate were also changed for arm64: the changes are the .patch files here, applied with
"patch -p1" inside the unpacked source.

Unpack one with:  dpkg-source -x NAME_VERSION.dsc

Everything else in the system is published by its makers; source-packages.tsv (next to this
archive in the release) lists every source package, its version and where it comes from:
  Ubuntu       https://launchpad.net/ubuntu/+source/NAME/VERSION, or apt-get source NAME=VERSION
  Linux Mint   http://packages.linuxmint.com/pool/ and https://github.com/linuxmint
  Mozilla      https://ftp.mozilla.org/pub/firefox/releases/ (Firefox and its language packs)
The build scripts, and the packages this project makes itself, are in the repository:
  $REPO_URL
EOF
bsdtar --no-mac-metadata --format ustar --uid 0 --gid 0 --uname root --gname root \
  -cf $REL/$SOURCES.tar -C $REL/.stage $SOURCES

log "packing the UTM virtual machine"
ln -f $OUT/$IMAGE $OUT/$ISO $REL/
repo_deb=($OUT/mint-arm-repo_*_all.deb(Nom[1]))
(( $#repo_deb )) && ln -f $repo_deb[1] $REL/
(cd $OUT && zip -q -r -X -1 $REL/${IMAGE%.img.xz}-utm.zip $BUNDLE -x '*.DS_Store')
rm -rf $REL/.stage
(cd $REL && shasum -a 256 *.img.xz *.zip *.iso *.deb(N) *.tar *.tsv > SHA256SUMS)
for f in $REL/*.img.xz $REL/*.zip $REL/*.iso; do
  (( $(stat -f %z $f) <= 2147483648 )) || { print -u2 "${f:t} is over GitHub's 2 GiB limit for a release file"; exit 1 }
done
log "Raspberry Pi Imager's entry: imager/os_list.json"
python3 - $REL/$IMAGE $ROOT/imager/os_list.json $REPO_URL $VERSION $RELEASE_DATE \
  "$(xz --robot --list $REL/$IMAGE | awk '$1 == "totals" {print $5}')" \
  "$(xz -dc $REL/$IMAGE | shasum -a 256 | cut -d' ' -f1)" "$(shasum -a 256 $REL/$IMAGE | cut -d' ' -f1)" <<'EOF'
import json, os, sys, urllib.request
image, out, repo_url, version, date, extract_size, extract_sha256, download_sha256 = sys.argv[1:9]
owner_repo = repo_url.split('github.com/')[1]
# Imager's own version and device list, as Raspberry Pi publishes them (or as last written here)
try:
    with urllib.request.urlopen('https://downloads.raspberrypi.com/os_list_imagingutility_v4.json', timeout=30) as r:
        official = json.load(r)['imager']
except Exception:
    official = json.load(open(out))['imager']
keep = ('Raspberry Pi 5', 'Raspberry Pi 4', 'No filtering')
imager = {k: official[k] for k in ('latest_version', 'url') if k in official}
imager['devices'] = [d for d in official['devices'] if d['name'] in keep]
entry = {
    'name': 'Linux Mint ARM 22.3 Cinnamon (unofficial)',
    'description': 'Linux Mint 22.3 "Zena" with Cinnamon, rebuilt for ARM64. Linux Mint\'s own setup asks for your '
                   'language, keyboard, time zone and account at the first start. Not made by the Linux Mint team.',
    'icon': f'https://raw.githubusercontent.com/{owner_repo}/main/imager/icon.png',
    'website': repo_url,
    'url': f'{repo_url}/releases/download/v{version}/{os.path.basename(image)}',
    'extract_size': int(extract_size),
    'extract_sha256': extract_sha256,
    'image_download_size': os.path.getsize(image),
    'image_download_sha256': download_sha256,
    'release_date': date,
    'init_format': 'none',
    'architecture': 'armv8',
    'devices': ['pi5-64bit', 'pi4-64bit'],
    'capabilities': [],
}
with open(out, 'w') as f:
    json.dump({'imager': imager, 'os_list': [entry]}, f, indent=2, ensure_ascii=False)
    f.write('\n')
EOF
log "release files for $VERSION in $REL:"
ls -l $REL
print "Commit imager/os_list.json with the release: Raspberry Pi Imager reads it from the repository."
