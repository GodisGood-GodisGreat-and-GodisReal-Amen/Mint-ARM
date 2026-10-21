# shellcheck shell=bash
# Shared helpers for the Linux Mint ARM build scripts that run in the build VM (sourced, not executed).

W=${W:-/srv/mintarm}
MINT_SUITE=${MINT_SUITE:-zena}
REPO_ORIGIN="Linux Mint ARM"

# sudo starts commands with a clean environment: keep apt non-interactive, and keep
# needrestart's report out of the logs.
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1
sudo() { command sudo --preserve-env=DEBIAN_FRONTEND,NEEDRESTART_SUSPEND "$@"; }

log() { printf '[%(%H:%M:%S)T] %s\n' -1 "$*"; }

# Index a flat apt repository. Its Origin is what the 700 pin (same as Linux Mint's own
# pin on its repository) matches, so Mint's versions win over newer-numbered Ubuntu ones.
index_repo() {
  local dir=$1
  (cd "$dir" && apt-ftparchive packages . > Packages && gzip -9nkf Packages \
     && apt-ftparchive -o APT::FTPArchive::Release::Origin="$REPO_ORIGIN" \
          -o APT::FTPArchive::Release::Label="$REPO_ORIGIN" \
          -o APT::FTPArchive::Release::Suite="$MINT_SUITE" \
          -o APT::FTPArchive::Release::Codename="$MINT_SUITE" \
          -o APT::FTPArchive::Release::Architectures="arm64 all" \
          release . > Release)
}
