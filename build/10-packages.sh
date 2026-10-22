#!/bin/bash
# Linux Mint ARM build, stage 10 (in the build VM): rebuild Linux Mint's architecture-specific
# packages for arm64 and gather Mint's architecture-independent ones into one local apt repository.
#
# Runs inside the Ubuntu 24.04 (noble) arm64 build VM as a user with passwordless sudo.
# Result: $W/repo (flat apt repo: arm64/*.deb rebuilt here, all/*.deb fetched from Mint).
# Running it again only builds what is missing.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"
MINT_MIRROR=${MINT_MIRROR:-http://packages.linuxmint.com}
MINT_KEY_FPR=302F0738F465C1535761F965A6616109451BBBF2   # Linux Mint Repository Signing Key
JOBS=${JOBS:-$(nproc)}
PAR=${PAR:-3}                     # packages built concurrently inside one layer

# Mint sources that ship arm64-relevant binaries, in build-dependency layers
# (each layer only build-depends on earlier ones). Firefox comes from Mozilla's
# arm64 apt repo instead; Thunderbird is not part of the image.
LAYERS=(
  "xapp cinnamon-desktop cinnamon-menus cjs libadwaita-1 libnma packagekit xdg-desktop-portal zenity base-files mate-desktop mate-menus mate-polkit slick-greeter cinnamon-screensaver celluloid file-roller gnome-calculator gnome-online-accounts-gtk gnome-screenshot gnome-terminal blueman fingwit onboard touchegg transmission warpinator"
  "cinnamon-settings-daemon cinnamon-session cinnamon-control-center nemo xreader xviewer xed pix timeshift network-manager-applet xdg-desktop-portal-xapp gnome-calendar simple-scan ubiquity"
  "muffin nemo-fileroller nemo-preview nemo-python nemo-share xviewer-plugins"
  "cinnamon"
)

reindex() {
  index_repo "$W/repo"
  sudo apt-get -qq update --allow-releaseinfo-change
}

setup() {
  sudo apt-get -qq update
  sudo apt-get -y -qq install --no-install-recommends build-essential devscripts equivs debhelper fakeroot \
    dpkg-dev apt-utils debootstrap dosfstools rsync zstd python3-apt gnupg curl dctrl-tools > /dev/null
  sudo mkdir -p "$W"/{src,repo/arm64,repo/all,logs,aptall/lists/partial,aptall/archives/partial}
  sudo chown -R "$(id -un):" "$W"
  sudo chmod 755 "$W" "$W/repo"
  if ! gpg -q --show-keys --with-colons /usr/share/keyrings/linuxmint-keyring.gpg 2>/dev/null | grep -q "^fpr:::::::::$MINT_KEY_FPR:" \
     || [ "$(file -b /usr/share/keyrings/linuxmint-keyring.gpg)" = "PGP public key block Public-Key (old)" ]; then
    local tmp; tmp=$(mktemp -d)
    local f; f=$(curl -fsS "$MINT_MIRROR/dists/$MINT_SUITE/main/binary-amd64/Packages.gz" | gunzip | grep-dctrl -n -s Filename -X -P linuxmint-keyring)
    curl -fsS -o "$tmp/k.deb" "$MINT_MIRROR/$f"
    dpkg-deb -x "$tmp/k.deb" "$tmp/x"
    # The package's /usr/share/keyrings copy is a 2016 export apt cannot verify with;
    # the trusted.gpg.d copy carries the current self-signature.
    local k=$tmp/x/etc/apt/trusted.gpg.d/linuxmint-keyring.gpg
    gpg -q --show-keys --with-colons "$k" | grep -q "^fpr:::::::::$MINT_KEY_FPR:" \
      || { echo "Mint keyring fingerprint mismatch" >&2; exit 1; }
    sudo install -m 644 "$k" /usr/share/keyrings/linuxmint-keyring.gpg
    rm -rf "$tmp"
  fi
  echo "deb-src [signed-by=/usr/share/keyrings/linuxmint-keyring.gpg] $MINT_MIRROR $MINT_SUITE main upstream import backport" \
    | sudo tee /etc/apt/sources.list.d/mint-src.list >/dev/null
  echo "deb [trusted=yes] file:$W/repo ./" | sudo tee /etc/apt/sources.list.d/mintarm-local.list >/dev/null
  touch "$W/repo/Packages"
  reindex
}

# Mint publishes binary-amd64 indexes only; its Architecture: all packages are listed there.
# A throwaway apt configuration with an amd64 view downloads them with signature checks.
fetch_arch_all() {
  local A=$W/aptall
  echo "deb [signed-by=/usr/share/keyrings/linuxmint-keyring.gpg] $MINT_MIRROR $MINT_SUITE main upstream import backport" > "$A/sources.list"
  : > "$A/status"
  mkdir -p "$A/empty"
  local o=(-o APT::Architecture=amd64 -o "APT::Architectures::=amd64" -o Dir::State::Lists="$A/lists"
           -o Dir::State::status="$A/status" -o Dir::Cache="$A" -o Dir::Etc::SourceList="$A/sources.list"
           -o Dir::Etc::SourceParts="$A/empty" -o Dir::Etc::Preferences="$A/empty/none" -o Dir::Etc::PreferencesParts="$A/empty")
  apt-get -qq "${o[@]}" update
  local pkgs
  pkgs=$(cat "$A"/lists/*_binary-amd64_Packages | grep-dctrl -n -s Package -F Architecture -X all \
         | grep -v -E '^(mint-backgrounds-|firefox|thunderbird)' | sort -u)
  pkgs+=$'\nmint-backgrounds-wallpapers'
  (cd "$W/repo/all" && apt-get -qq "${o[@]}" download $pkgs)
  log "fetched $(ls "$W/repo/all" | wc -l) Architecture: all packages from Mint"
}

fetch_src() {
  local p=$1
  rm -rf "${W:?}/src/$p" && mkdir -p "$W/src/$p"
  (cd "$W/src/$p" && apt-get source -qq --only-source "$p" > /dev/null)
}

srcdir() { find "$W/src/$1" -mindepth 1 -maxdepth 1 -type d | head -1; }

build_one() {
  local p=$1 d; d=$(srcdir "$p")
  local j=$(( (JOBS + PAR - 1) / PAR ))
  if (cd "$d" && DEB_BUILD_OPTIONS="nocheck nodoc noautodbgsym parallel=$j" \
        dpkg-buildpackage -B -uc -us > "$W/logs/$p.log" 2>&1); then
    log "OK   $p $(dpkg-parsechangelog -l "$d/debian/changelog" -S Version)"
  else
    log "FAIL $p (see $W/logs/$p.log)"; return 1
  fi
}
export -f build_one srcdir log
export W JOBS PAR

main() {
  setup
  [ -n "$(ls -A "$W/repo/all")" ] || fetch_arch_all
  reindex
  local n=0 failed=0
  for layer in "${LAYERS[@]}"; do
    n=$((n + 1)); log "layer $n: $layer"
    local todo=()
    for p in $layer; do
      if ls "$W/src/$p"/*_arm64.deb > /dev/null 2>&1; then continue; fi
      fetch_src "$p"
      if ! sudo apt-get -y -qq --no-install-recommends build-dep --arch-only "$(srcdir "$p")" > "$W/logs/$p.deps.log" 2>&1; then
        log "FAIL $p (build-deps, see $W/logs/$p.deps.log)"; failed=1; continue
      fi
      todo+=("$p")
    done
    if [ ${#todo[@]} -gt 0 ]; then
      printf '%s\n' "${todo[@]}" | xargs -P "$PAR" -I{} bash -c 'build_one {}' || failed=1
    fi
    find "$W/src" -maxdepth 2 -name '*_arm64.deb' -exec cp -f {} "$W/repo/arm64/" \;
    reindex
  done
  log "done: $(ls "$W/repo/arm64" | wc -l) arm64 packages, $(ls "$W/repo/all" | wc -l) all packages"
  if [ $failed -ne 0 ]; then
    log "some packages did not build (see the FAIL lines above); running this again retries only those"
    exit 1
  fi
}

main "$@"
