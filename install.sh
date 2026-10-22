#!/bin/zsh
# Linux Mint ARM: the ready-made virtual machine, into UTM, with one command:
#
#   /bin/zsh -c "$(curl -fsSL https://raw.githubusercontent.com/GodisGood-GodisGreat-and-GodisReal-Amen/Mint-ARM/main/install.sh)"
#
# On a Mac with Apple silicon it checks the Mac, installs UTM if it is missing (after asking),
# downloads the latest release's virtual machine, checks it against the release's SHA256SUMS,
# unpacks it into ~/Virtual Machines and opens it in UTM. Nothing else on the Mac changes.
#
# usage: install.sh [--dir DIR] [--utm-dir DIR] [--no-open] [--yes]
#   --dir DIR      where the virtual machine goes (default: ~/Virtual Machines)
#   --utm-dir DIR  where UTM goes if it has to be installed (default: /Applications)
#   --no-open      leave the virtual machine there without opening UTM
#   --yes          answer yes to the question about installing UTM
# For tests: MINT_ARM_RELEASE (the release files' base URL, file:// included) and MINT_ARM_UTM_APP
# (where to look for UTM) replace their defaults.
emulate -L zsh
setopt err_exit pipe_fail no_unset

REPO=GodisGood-GodisGreat-and-GodisReal-Amen/Mint-ARM
ZIP=linuxmint-22.3-cinnamon-arm64-unofficial-utm.zip
VM="Linux Mint 22.3 ARM.utm"
UTM_TEAM=WDNLXAD4W8      # the Apple developer ID that signs UTM (Turing Software, LLC)
UTM_MIN=4.7              # the ready-made VM is made for UTM 4.7 and newer
DIR="$HOME/Virtual Machines" UTM_DIR=/Applications OPEN=1 YES=0

say() { print -r -- "==> $*" }
note() { print -r -- "    $*" }
fail() { print -ru2 -- "Error: $*"; exit 1 }
usage() {
  print -r -- "Installs Linux Mint ARM's ready-made virtual machine into UTM.
usage: install.sh [--dir DIR] [--utm-dir DIR] [--no-open] [--yes]
  --dir DIR      where the virtual machine goes (default: ~/Virtual Machines)
  --utm-dir DIR  where UTM goes if it has to be installed (default: /Applications)
  --no-open      leave the virtual machine there without opening UTM
  --yes          answer yes to the question about installing UTM"
  exit ${1:-0}
}
ask() {   # QUESTION: yes or no, from the keyboard even when the script comes through a pipe
  (( YES )) && return 0
  local reply
  read -r "reply?$1 [y/N] " < /dev/tty || return 1
  [[ $reply == [yY]* ]]
}

while (( $# )); do
  case $1 in
    --dir) DIR=${2:?--dir needs a folder}; shift ;;
    --utm-dir) UTM_DIR=${2:?--utm-dir needs a folder}; shift ;;
    --no-open) OPEN=0 ;;
    --yes|-y) YES=1 ;;
    -h|--help) usage ;;
    *) print -ru2 -- "unknown option: $1"; usage 1 ;;
  esac
  shift
done
DIR=${DIR:A} UTM_DIR=${UTM_DIR:A}

# --- the Mac
(( EUID != 0 )) || fail "run this as yourself, not with sudo: the virtual machine belongs in your own folders"
[[ $(uname -s) == Darwin && $(sysctl -in hw.optional.arm64) == 1 ]] \
  || fail "Linux Mint ARM needs a Mac with Apple silicon (M1 or newer)"
mkdir -p $DIR
free_gb=$(( $(df -k $DIR | awk 'NR == 2 {print $4}') / 1048576 ))
(( free_gb >= 6 )) || fail "there are $free_gb GB free on the disk of $DIR; 6 GB are needed (2 to download, 2 for the VM, room to grow)"
[[ ! -e "$DIR/$VM" ]] || fail "$DIR/$VM is already there. Move or rename it (it may hold your system), or choose another folder with --dir"

# --- UTM
version_ok() { [[ $(printf '%s\n%s\n' $UTM_MIN $1 | sort -V | head -1) == $UTM_MIN ]] }
find_utm() {
  local app
  for app in ${MINT_ARM_UTM_APP:-} /Applications/UTM.app $HOME/Applications/UTM.app \
             ${(f)"$(mdfind "kMDItemCFBundleIdentifier == 'com.utmapp.UTM'" 2> /dev/null)"}; do
    [[ -n ${MINT_ARM_UTM_APP:-} && $app != ${MINT_ARM_UTM_APP} ]] && continue
    [[ -d $app/Contents ]] && { print -r -- $app; return 0 }
  done
  return 1
}
install_utm() {
  say "Installing UTM from github.com/utmapp/UTM"
  local tmp; tmp=$(mktemp -d)
  curl -fL --retry 3 -# -o $tmp/UTM.dmg https://github.com/utmapp/UTM/releases/latest/download/UTM.dmg \
    || fail "UTM's download failed; get it from https://mac.getutm.app"
  hdiutil attach -nobrowse -readonly -quiet -mountpoint $tmp/mnt $tmp/UTM.dmg || fail "could not open UTM.dmg"
  local app=$tmp/mnt/UTM.app team
  team=$(codesign -dv $app 2>&1 | awk -F= '/^TeamIdentifier=/ {print $2}')
  if ! codesign --verify --deep --strict $app 2> /dev/null || [[ $team != $UTM_TEAM ]] \
     || ! spctl --assess --type execute $app 2> /dev/null; then
    hdiutil detach -quiet $tmp/mnt; rm -rf $tmp
    fail "the downloaded UTM is not signed by UTM's developer or not notarized by Apple: not installed"
  fi
  mkdir -p $UTM_DIR
  [[ -w $UTM_DIR ]] || { hdiutil detach -quiet $tmp/mnt; rm -rf $tmp; fail "cannot write to $UTM_DIR: try --utm-dir ~/Applications" }
  ditto $app $UTM_DIR/UTM.app
  hdiutil detach -quiet $tmp/mnt; rm -rf $tmp
  note "UTM $(defaults read $UTM_DIR/UTM.app/Contents/Info CFBundleShortVersionString) is in $UTM_DIR (signed by UTM's developer, notarized by Apple)"
  UTM_APP=$UTM_DIR/UTM.app
}
if UTM_APP=$(find_utm); then
  utm_version=$(defaults read $UTM_APP/Contents/Info CFBundleShortVersionString 2> /dev/null || print 0)
  say "UTM $utm_version found ($UTM_APP)"
  version_ok $utm_version || ask "This UTM is older than $UTM_MIN, which the virtual machine needs; update UTM from https://mac.getutm.app first. Continue anyway?" \
    || exit 1
else
  say "UTM, the free virtual machine app, is not installed"
  ask "Download it from its developer (github.com/utmapp/UTM) and install it in $UTM_DIR?" \
    || { note "Get UTM from https://mac.getutm.app, then run this again."; exit 1 }
  install_utm
fi

# --- the virtual machine
if [[ -n ${MINT_ARM_RELEASE:-} ]]; then
  BASE=$MINT_ARM_RELEASE TAG=test
else
  latest=$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/$REPO/releases/latest) \
    || fail "cannot reach github.com; check the connection"
  TAG=${latest:t}
  [[ $TAG == v* ]] || fail "cannot find the latest release on github.com/$REPO"
  BASE=https://github.com/$REPO/releases/download/$TAG
fi
CACHE=$HOME/Library/Caches/mint-arm-installer
mkdir -p $CACHE
say "Downloading Linux Mint ARM ${TAG#v} (about 1.75 GB; if it stops, running this again resumes it)"
curl -fL --retry 3 -C - -# -o $CACHE/$TAG-$ZIP "$BASE/$ZIP" || fail "the download stopped; run this again to resume it"
curl -fsSL --retry 3 -o $CACHE/$TAG-SHA256SUMS "$BASE/SHA256SUMS" || fail "could not download SHA256SUMS"
say "Checking it against the release's SHA256SUMS"
expected=$(awk -v f=$ZIP '$2 == f {print $1}' $CACHE/$TAG-SHA256SUMS)
actual=$(shasum -a 256 $CACHE/$TAG-$ZIP | cut -d' ' -f1)
if [[ -z $expected || $expected != $actual ]]; then
  rm -f $CACHE/$TAG-$ZIP
  fail "the download does not match the release's checksum (deleted); run this again"
fi
note "SHA-256 $actual: matches"
say "Unpacking it into $DIR"
ditto -x -k $CACHE/$TAG-$ZIP $DIR || fail "could not unpack the virtual machine"
[[ -d "$DIR/$VM" ]] || fail "the download held no $VM"
rm -f $CACHE/$TAG-$ZIP $CACHE/$TAG-SHA256SUMS
rmdir $CACHE 2> /dev/null || true

if (( OPEN )); then
  say "Opening it in UTM"
  open -a $UTM_APP "$DIR/$VM"
  note "UTM now lists \"Linux Mint 22.3 ARM\". Press ▶ to start it: Linux Mint's setup asks for your"
  note "language, keyboard, time zone and account, then starts the desktop."
else
  note "The virtual machine is in $DIR/$VM; double-click it to add it to UTM."
fi
note "Guide: https://github.com/$REPO/blob/main/docs/getting-started.md"
