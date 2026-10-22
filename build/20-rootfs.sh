#!/bin/bash
# Linux Mint ARM build, stage 20 (in the build VM): assemble the system in $W/rootfs from Ubuntu
# ports and the rebuilt Mint packages, following the original Mint 22.3 manifest trimmed by
# packages.conf. One system for the Raspberry Pi and for virtual machines: it carries both
# machines' kernels and boot tools, and its first start removes the half it does not use
# (mint-arm-system's first-start service). It is prepared for Linux Mint's first-start setup the
# way Mint's installer prepares an OEM installation. Runs after 10-packages.sh and 15-mintarm.sh;
# 30-image.sh makes the disk images.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
R=$W/rootfs
L=$W/logs/rootfs   # log file prefix
UBUNTU_MIRROR=${UBUNTU_MIRROR:-http://ports.ubuntu.com/ubuntu-ports}
SUITE=noble
MANIFEST=$HERE/mint-22.3-cinnamon-amd64.manifest
REPO_FILE_LIMIT=3000000      # arch:all Mint debs above this size stay out of the local archive

in_root() {
  sudo chroot "$R" /usr/bin/env -i HOME=/root TERM=dumb LANG=C.UTF-8 \
    PATH=/usr/sbin:/usr/bin:/sbin:/bin DEBIAN_FRONTEND=noninteractive "$@"
}
APT=(apt-get -y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold
     -o APT::Install-Recommends=false)

mount_all() {
  local d
  for d in dev dev/pts proc sys; do mountpoint -q "$R/$d" || sudo mount --bind "/$d" "$R/$d"; done
  mountpoint -q "$R/run" || sudo mount -t tmpfs -o mode=755 tmpfs "$R/run"
  sudo mkdir -p "$R/mnt/mintarm-repo"
  mountpoint -q "$R/mnt/mintarm-repo" || sudo mount --bind "$W/repo" "$R/mnt/mintarm-repo"
}
umount_all() {
  local d
  for d in mnt/mintarm-repo run sys proc dev/pts dev; do
    if mountpoint -q "$R/$d"; then sudo umount "$R/$d" 2>/dev/null || sudo umount -l "$R/$d"; fi
  done
}

# Every run starts from a fresh debootstrap, so nothing from an earlier run is left in the
# system. (--one-file-system: never descend into a mount left behind by an interrupted run.)
bootstrap() {
  umount_all
  sudo rm -rf --one-file-system "$R"
  log "debootstrap $SUITE arm64"
  sudo debootstrap --arch=arm64 --components=main,restricted,universe,multiverse \
    "$SUITE" "$R" "$UBUNTU_MIRROR" > "$W/logs/debootstrap.log" 2>&1
}

write_official_sources() {   # $1 = with Linux Mint's own line (needs linuxmint-keyring)
  {
    [ "${1:-}" = mint ] && printf 'deb http://packages.linuxmint.com %s main upstream import backport #id:linuxmint_main\n\n' "$MINT_SUITE"
    printf 'deb %s %s main restricted universe multiverse\n' "$UBUNTU_MIRROR" "$SUITE"
    printf 'deb %s %s-updates main restricted universe multiverse\n' "$UBUNTU_MIRROR" "$SUITE"
    printf 'deb %s %s-backports main restricted universe multiverse\n\n' "$UBUNTU_MIRROR" "$SUITE"
    printf 'deb %s/ %s-security main restricted universe multiverse\n' "$UBUNTU_MIRROR" "$SUITE"
  } | sudo tee "$R/etc/apt/sources.list.d/official-package-repositories.list" > /dev/null
}

configure_apt() {
  printf '#!/bin/sh\nexit 101\n' | sudo tee "$R/usr/sbin/policy-rc.d" > /dev/null
  sudo chmod 755 "$R/usr/sbin/policy-rc.d"
  sudo rm -f "$R/etc/resolv.conf" && sudo cp -L /etc/resolv.conf "$R/etc/resolv.conf"
  echo "# Linux Mint keeps its sources in /etc/apt/sources.list.d/official-package-repositories.list" \
    | sudo tee "$R/etc/apt/sources.list" > /dev/null
  sudo rm -f "$R/etc/apt/sources.list.d/ubuntu.sources"
  write_official_sources
  echo "deb [trusted=yes] file:/mnt/mintarm-repo ./" | sudo tee "$R/etc/apt/sources.list.d/zz-mintarm-build.list" > /dev/null
  printf 'Package: *\nPin: release o=%s\nPin-Priority: 700\n' "$REPO_ORIGIN" \
    | sudo tee "$R/etc/apt/preferences.d/zz-mintarm-build.pref" > /dev/null
  in_root apt-get -q update > "$L-apt-update.log"
  # Mozilla's apt source and pin come with mint-arm-system; Mint's key with linuxmint-keyring.
  # mint-arm-pi brings the Raspberry Pi kernel, which asks for linux-firmware:
  # linux-firmware-minimal (empty) stands in for Ubuntu's whole firmware set when it goes in at
  # the same time.
  in_root "${APT[@]}" install mint-arm-system mint-arm-vm mint-arm-pi linuxmint-keyring linux-firmware-minimal \
    > "$L-base.log"
  in_root apt-get -q update >> "$L-apt-update.log"
}

install_packages() {
  in_root apt-cache pkgnames | sort -u > "$W/rootfs-available.txt"
  python3 "$HERE/select-packages.py" "$MANIFEST" "$HERE/roots.txt" "$W/rootfs-available.txt" \
    "$W/rootfs-install.txt" "$W/rootfs-manual.txt" "$HERE/packages.conf"
  log "installing $(wc -l < "$W/rootfs-install.txt") packages"
  if ! in_root "${APT[@]}" install $(cat "$W/rootfs-install.txt") > "$L-install.log" 2>&1; then
    grep -E '^(E:| )' "$L-install.log" | tail -40; return 1
  fi
  # debootstrap installs from the release pocket; bring every package to its current update
  in_root "${APT[@]}" dist-upgrade > "$L-upgrade.log" 2>&1
  log "upgraded $(grep -c '^Setting up ' "$L-upgrade.log" || true) packages to their current updates"
}

prune() {
  in_root dpkg-query -W -f '${Package}\n' | sort -u > "$W/rootfs-installed.txt"
  in_root apt-mark auto $(cat "$W/rootfs-installed.txt") > /dev/null
  in_root apt-mark manual $(comm -12 "$W/rootfs-installed.txt" <(sort -u "$W/rootfs-manual.txt")) > /dev/null
  in_root "${APT[@]}" --purge autoremove > "$L-autoremove.log"
  log "autoremoved $(grep -c '^Removing ' "$L-autoremove.log" || true) packages only needed by dropped software"
}

configure_system() {
  echo mint | sudo tee "$R/etc/hostname" > /dev/null
  printf '127.0.0.1\tlocalhost\n127.0.1.1\tmint\n\n::1\tip6-localhost ip6-loopback\nfe00::0\tip6-localnet\nff00::0\tip6-mcastprefix\nff02::1\tip6-allnodes\nff02::2\tip6-allrouters\n' \
    | sudo tee "$R/etc/hosts" > /dev/null
  echo LANG=C.UTF-8 | sudo tee "$R/etc/default/locale" > /dev/null
  printf 'XKBMODEL="pc105"\nXKBLAYOUT="us"\nXKBVARIANT=""\nXKBOPTIONS=""\n\nBACKSPACE="guess"\n' \
    | sudo tee "$R/etc/default/keyboard" > /dev/null
  echo Etc/UTC | sudo tee "$R/etc/timezone" > /dev/null
  sudo ln -sf /usr/share/zoneinfo/Etc/UTC "$R/etc/localtime"
  sudo mkdir -p "$R/etc/netplan"
  printf 'network:\n  version: 2\n  renderer: NetworkManager\n' | sudo tee "$R/etc/netplan/01-network-manager-all.yaml" > /dev/null
  sudo chmod 600 "$R/etc/netplan/01-network-manager-all.yaml"
  # the image's partitions (30-image.sh), by label as on Ubuntu's Raspberry Pi images; fstrim.timer
  # trims them weekly. In a virtual machine, the first start mounts the boot partition at /boot/efi.
  printf 'LABEL=writable\t/\text4\tdefaults\t0\t1\nLABEL=system-boot\t/boot/firmware\tvfat\tdefaults\t0\t1\n' \
    | sudo tee "$R/etc/fstab" > /dev/null
  sudo mkdir -p "$R/boot/firmware"
  sudo tee "$R/etc/default/grub" > /dev/null <<'EOF'
# If you change this file, run 'update-grub' afterwards to update
# /boot/grub/grub.cfg.

GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR=`( . /etc/os-release; echo ${NAME:-Ubuntu} ) 2>/dev/null || echo Ubuntu`
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""
EOF
  in_root locale-gen en_US.UTF-8 > /dev/null
  write_official_sources mint
}

# The "Linux Mint ARM" archive installed into the system: every arm64 package rebuilt here,
# Mint's small arch:all packages, and any Mint package Ubuntu ships a newer-numbered version
# of. Its 700 pin keeps Mint's versions in place across Ubuntu updates, as Mint's own repo does.
make_repo_package() {
  local pkg=$W/mint-arm-repo deb
  build_repo_package
  deb=$(ls "$pkg"/mint-arm-repo_*.deb)
  sudo cp "$deb" "$R/tmp/"
  in_root dpkg -i "/tmp/${deb##*/}" > /dev/null
  sudo rm -f "$R"/tmp/mint-arm-repo_*.deb
}
build_repo_package() {
  export GNUPGHOME=$W/gnupg
  if [ ! -d "$GNUPGHOME" ]; then
    mkdir -m 700 -p "$GNUPGHOME"
    gpg --batch --pinentry-mode loopback --passphrase '' \
      --quick-gen-key "Linux Mint ARM local archive <mint-arm@localhost>" ed25519 sign never 2> /dev/null
  fi
  local pkg=$W/mint-arm-repo root=$W/mint-arm-repo/root
  rm -rf "$pkg" && mkdir -p "$root/usr/share/mint-arm/repo" "$root/DEBIAN"
  cat "$W"/aptall/lists/*_dists_"$MINT_SUITE"_main_binary-amd64_Packages \
    | grep-dctrl -n -s Package -F Architecture -X all | sort -u > "$W/mint-main.txt"
  log "mint-arm-repo selection: $(python3 "$HERE/select-repo.py" "$W/repo" "$R" "$W/mint-main.txt" \
         "$root/usr/share/mint-arm/repo" "$REPO_FILE_LIMIT" "$MANIFEST")"
  index_repo "$root/usr/share/mint-arm/repo"
  gpg --batch --yes --clearsign -o "$root/usr/share/mint-arm/repo/InRelease" "$root/usr/share/mint-arm/repo/Release"
  install -d "$root/usr/share/keyrings" "$root/etc/apt/sources.list.d" "$root/etc/apt/preferences.d"
  gpg --export > "$root/usr/share/keyrings/mint-arm-archive.gpg"
  echo "deb [signed-by=/usr/share/keyrings/mint-arm-archive.gpg] file:/usr/share/mint-arm/repo ./" \
    > "$root/etc/apt/sources.list.d/mint-arm.list"
  printf '# Same rule as Linux Mint'"'"'s own repository pin: Mint'"'"'s versions win over Ubuntu'"'"'s.\nPackage: *\nPin: release o=%s\nPin-Priority: 700\n' "$REPO_ORIGIN" \
    > "$root/etc/apt/preferences.d/mint-arm.pref"
  printf '/etc/apt/sources.list.d/mint-arm.list\n/etc/apt/preferences.d/mint-arm.pref\n' > "$root/DEBIAN/conffiles"
  cat > "$root/DEBIAN/control" <<EOF
Package: mint-arm-repo
Version: $(dpkg-deb -f "$(ls "$W"/repo/all/mint-arm-system_*.deb | sort -V | tail -1)" Version)
Architecture: all
Maintainer: Linux Mint ARM local build <mint-arm@localhost>
Section: admin
Priority: optional
Description: Linux Mint ARM64 package archive
 The arm64 builds of Linux Mint's own packages, as a local apt archive. Its pin keeps
 Linux Mint's versions installed when Ubuntu publishes higher-numbered ones (the same
 rule Linux Mint applies to its own repository), and it lets the Software Manager
 install Linux Mint applications that are not preinstalled.
EOF
  chmod -R go-w "$root"
  dpkg-deb --root-owner-group -Zxz --build "$root" "$pkg/" > /dev/null
  log "mint-arm-repo: $(find "$root/usr/share/mint-arm/repo" -name '*.deb' | wc -l) packages, $(du -sh "$root/usr/share/mint-arm/repo" | cut -f1)"
}

# The system gets what Ubiquity's OEM installation did to the virtual machine of earlier releases:
# the live-only packages come out (Mint's list, the same the installer removes), the first-start
# wizard goes back in with the temporary "oem" account it deletes when it is done, and the system
# starts into that wizard. Before the wizard, the first-start service removes what the machine
# does not use (the build leaves it the marker that it is pending).
first_start() {
  local extra
  in_root dpkg-query -W -f '${Package}\n' | sort -u > "$W/installed.names"
  # (less GRUB and shim, which Mint's installer removes on PCs but virtual machines start with)
  sed 's/:.*//' "$HERE/mint-22.3-cinnamon-amd64.manifest-remove" | sort -u | grep -v -E '^(grub-efi-|shim-signed)' \
    | comm -12 - "$W/installed.names" > "$W/live-only.txt"
  # what else removing them takes along (expected: nothing the system needs)
  extra=$(in_root apt-get -s purge $(cat "$W/live-only.txt") | awk '/^Purg /{print $2}' | sort \
          | comm -23 - "$W/live-only.txt" | xargs)
  {
    in_root "${APT[@]}" purge $(cat "$W/live-only.txt") \
      && in_root "${APT[@]}" install oem-config-gtk \
      && in_root "${APT[@]}" --purge autoremove
  } > "$L-firststart.log" 2>&1 || { grep -E '^(E:|W:| )' "$L-firststart.log" | tail -20; return 1; }
  in_root useradd -d /home/oem -G adm,sudo -m -N -u 29999 oem
  in_root passwd -l oem > /dev/null
  in_root oem-config-prepare --quiet
  sudo install -d "$R/var/lib/mint-arm" && sudo touch "$R/var/lib/mint-arm/first-start-pending"
  # the initrds as the system now stands (made, for a kernel that went in before initramfs-tools)
  local kver
  : > "$L-initramfs.log"
  for kver in $(in_root linux-version list); do
    if [ -e "$R/boot/initrd.img-$kver" ]; then
      in_root update-initramfs -u -k "$kver" >> "$L-initramfs.log" 2>&1
    else
      in_root update-initramfs -c -k "$kver" >> "$L-initramfs.log" 2>&1
    fi
  done
  log "first start: $(wc -l < "$W/live-only.txt") live-only packages removed${extra:+ (with them: $extra)}, oem-config prepared"
}

finish() {
  sudo rm -f "$R/etc/apt/sources.list.d/zz-mintarm-build.list" "$R/etc/apt/preferences.d/zz-mintarm-build.pref"
  in_root apt-get -q update > /dev/null 2>&1 || true
  # expected here: only Mint's large artwork packages (themes, icons, wallpapers), which the
  # local archive leaves out because no Ubuntu package competes with them
  log "installed without an apt source:$(in_root apt list --installed 2>/dev/null | grep ',local\]' | cut -d/ -f1 | xargs)"
  in_root apt-get clean
  sudo rm -f "$R/usr/sbin/policy-rc.d" "$R/etc/resolv.conf"
  sudo ln -s ../run/systemd/resolve/stub-resolv.conf "$R/etc/resolv.conf"
  : | sudo tee "$R/etc/machine-id" > /dev/null
  sudo rm -f "$R/var/lib/dbus/machine-id"
  sudo rm -rf "$R"/tmp/* "$R"/var/tmp/* "$R"/var/cache/apt/*.bin "$R"/var/lib/apt/lists/*_* "$R"/root/.bash_history
  sudo rmdir "$R"/root/.cache "$R"/root/.ssh 2>/dev/null || true
  sudo find "$R/var/log" -type f -delete
  sudo rm -f "$R"/var/lib/dpkg/*-old "$R"/var/cache/debconf/*-old
  in_root dpkg-query -W --showformat='${Package}\t${Version}\n' > "$W/filesystem.manifest"
  log "rootfs ready: $(wc -l < "$W/filesystem.manifest") packages, $(sudo du -shx --exclude=mintarm-repo "$R" | cut -f1)"
}

trap umount_all EXIT
bootstrap
mount_all
configure_apt
install_packages
prune
configure_system
make_repo_package
first_start
finish
