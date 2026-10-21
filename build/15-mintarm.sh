#!/bin/bash
# Linux Mint ARM build, stage 15 (in the build VM): the arm64 adaptations made on top of
# Linux Mint's packages.
#  - mintsources (Software Sources) patched to use ports.ubuntu.com
#  - mintupdate (Update Manager) patched to recognise the installed kernel line
#  - mint-arm-system: zram, journal size, Firefox from Mozilla, Rosetta helper
#  - firefox-locale-* transitional packages that point at Mozilla's language packs
# Runs inside the build VM after 10-packages.sh; adds its packages to $W/repo.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
MOZILLA_KEY_URL=https://packages.mozilla.org/apt/repo-signing-key.gpg
MOZILLA_KEY_FPR=35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3
ARM_SUFFIX=+arm64.1

build_patched() {
  local pkg=$1 patch=$2 note=$3 cache=$W/srccache/$1
  if ! ls "$cache"/*.dsc > /dev/null 2>&1; then
    mkdir -p "$cache" && (cd "$cache" && apt-get source -qq --download-only --only-source "$pkg" > /dev/null)
  fi
  rm -rf "${W:?}/patched/$pkg" && mkdir -p "$W/patched/$pkg"
  cd "$W/patched/$pkg"
  dpkg-source -q -x "$(ls "$cache"/*.dsc | sort -V | tail -1)" > /dev/null
  cd "$(find . -mindepth 1 -maxdepth 1 -type d | head -1)"
  patch -p1 --no-backup-if-mismatch < "$patch"
  local v; v=$(dpkg-parsechangelog -S Version)
  DEBEMAIL=mint-arm@localhost DEBFULLNAME="Linux Mint ARM local build" \
    dch -v "$v$ARM_SUFFIX" -D "$(dpkg-parsechangelog -S Distribution)" "$note"
  sudo apt-get -y -qq --no-install-recommends build-dep ./ > /dev/null
  dpkg-buildpackage -b -uc -us > "$W/logs/$pkg-arm.log" 2>&1
  cp -f ../*"$ARM_SUFFIX"_*.deb "$W/repo/all/"
  log "OK   $pkg $v$ARM_SUFFIX"
}

build_system_package() {
  local root=$W/patched/mint-arm-system
  rm -rf "$root" && mkdir -p "$W/patched" && cp -a "$HERE/mint-arm-system" "$root"
  local tmp; tmp=$(mktemp -d)
  curl -fsS -o "$tmp/key" "$MOZILLA_KEY_URL"
  gpg -q --show-keys --with-colons "$tmp/key" | grep -q "^fpr:::::::::$MOZILLA_KEY_FPR:" \
    || { echo "Mozilla key fingerprint mismatch" >&2; exit 1; }
  install -D -m 644 "$tmp/key" "$root/etc/apt/keyrings/packages.mozilla.org.asc"
  echo /etc/apt/keyrings/packages.mozilla.org.asc >> "$root/DEBIAN/conffiles"
  rm -rf "$tmp"
  chmod -R go-w "$root"
  rm -f "$W"/repo/all/mint-arm-system_*.deb   # only the version built now
  dpkg-deb --root-owner-group -Zxz --build "$root" "$W/repo/all/" > /dev/null
  log "OK   mint-arm-system $(dpkg-deb -f "$W"/repo/all/mint-arm-system_*.deb Version)"
}

# The installer and Mint's Language Settings install Firefox translations as firefox-locale-XX.
# Ubuntu's packages of that name wrap the Firefox snap and conflict with Mozilla's Firefox, so
# these transitional packages pull in Mozilla's firefox-l10n-XX language packs instead.
build_firefox_locales() {
  local out=$W/patched/firefox-locales mozilla name code want recs
  rm -rf "$out" && mkdir -p "$out"
  rm -f "$W"/repo/all/firefox* "$W"/repo/all/thunderbird*
  mozilla=$(curl -fsS https://packages.mozilla.org/apt/dists/mozilla/main/binary-all/Packages \
            | sed -n 's/^Package: \(firefox-l10n-.*\)$/\1/p' | sort -u)
  for name in $(apt-cache pkgnames firefox-locale- | sort -u); do
    code=${name#firefox-locale-}
    case $code in zh-hans) want=zh-cn ;; zh-hant) want=zh-tw ;; *) want=$code ;; esac
    recs=$(grep -x "firefox-l10n-$want" <<< "$mozilla" || grep "^firefox-l10n-$want-" <<< "$mozilla" || true)
    mkdir -p "$out/$name/DEBIAN"
    {
      printf 'Package: %s\nVersion: 2:1.0%s\nArchitecture: all\n' "$name" "$ARM_SUFFIX"
      printf 'Maintainer: Linux Mint ARM local build <mint-arm@localhost>\nDepends: firefox\n'
      if [ -n "$recs" ]; then printf 'Recommends: %s\n' "$(echo $recs | sed 's/ /, /g')"; fi
      printf 'Section: localization\nPriority: optional\n'
      printf 'Description: Firefox language pack (%s) - transitional package\n' "$code"
      printf " Installs Mozilla's Firefox language pack for this language. Ubuntu's package of\n"
      printf ' this name installs the Firefox snap, which Linux Mint does not use.\n'
    } > "$out/$name/DEBIAN/control"
    chmod -R go-w "$out/$name"
    dpkg-deb --root-owner-group --build "$out/$name" "$W/repo/all/" > /dev/null
  done
  log "OK   firefox-locale-* ($(ls "$W"/repo/all/firefox-locale-*.deb | wc -l) transitional packages)"
}

build_patched mintsources "$HERE/patches/mintsources-ubuntu-ports.patch" \
  "Use ports.ubuntu.com (base, security and mirror list) on architectures other than amd64/i386."
build_patched mintupdate "$HERE/patches/mintupdate-arm-kernels.patch" \
  "Count the installed virtual kernel metapackage; never offer 64k-page kernels (arm64)."
build_system_package
build_firefox_locales
index_repo "$W/repo"
sudo apt-get -qq update --allow-releaseinfo-change
