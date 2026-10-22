#!/usr/bin/python3
"""Choose which Linux Mint packages go into the image's local "Linux Mint ARM" archive.

usage: select-repo.py BUILD_REPO ROOTFS MINT_MAIN_PACKAGES OUT_DIR SIZE_LIMIT [MANIFEST]

  - every arm64 package rebuilt from Mint's sources (except -dbg and -doc), and the packages
    made for this build (version suffix +arm64: patched Mint tools, Firefox locale transitions)
  - any Mint package Ubuntu ships a higher-numbered version of: its entry carries the 700
    pin that keeps Mint's version installed (as Mint's own repository pin does)
  - Mint's arch:all packages up to SIZE_LIMIT bytes that belong to a rebuilt source, are
    installed in the image, are in the original Linux Mint selection (MANIFEST: so what this
    build leaves out installs as Linux Mint ships it), or are Mint applications (Mint's "main"
    component)
Run inside the build VM with the rootfs apt lists still present (needs python3-apt).
"""
import glob
import os
import shutil
import subprocess
import sys

import apt_pkg

build_repo, rootfs, main_list, out_dir, limit = sys.argv[1:6]
limit = int(limit)
in_manifest = set()
if len(sys.argv) > 6:
    in_manifest = {line.split()[0].split(':')[0] for line in open(sys.argv[6]) if line.strip()}

apt_pkg.init_config()
apt_pkg.config.set('Dir', rootfs)
apt_pkg.config.set('Dir::State::status', os.path.join(rootfs, 'var/lib/dpkg/status'))
apt_pkg.config.set('Dir::Cache::pkgcache', '')
apt_pkg.config.set('Dir::Cache::srcpkgcache', '')
apt_pkg.init_system()
cache = apt_pkg.Cache(None)

def ubuntu_version(name):
    best = None
    if name in cache:
        for ver in cache[name].version_list:
            if any(pf.site.endswith('ports.ubuntu.com') for pf, _ in ver.file_list):
                if best is None or apt_pkg.version_compare(ver.ver_str, best) > 0:
                    best = ver.ver_str
    return best

def installed(name):
    return name in cache and cache[name].current_ver is not None

def fields(path):
    out = subprocess.run(['dpkg-deb', '-f', path, 'Package', 'Version', 'Architecture', 'Source'],
                         capture_output=True, text=True, check=True).stdout
    f = dict(line.split(': ', 1) for line in out.splitlines() if ': ' in line)
    return f['Package'], f['Version'], f['Architecture'], f.get('Source', f['Package']).split()[0]

newest = {}
for path in glob.glob(os.path.join(build_repo, '*', '*.deb')):
    name, version, arch, source = fields(path)
    if name not in newest or apt_pkg.version_compare(version, newest[name][1]) > 0:
        newest[name] = (path, version, arch, source)

rebuilt_sources = {source for _, _, arch, source in newest.values() if arch != 'all'}
mint_main = {line.strip() for line in open(main_list) if line.strip()}
skip_patterns = ('-dbg', '-doc', '-dbgsym')
chosen = []
for name, (path, version, arch, source) in sorted(newest.items()):
    if name.endswith(skip_patterns) or name.startswith('thunderbird'):
        continue
    if name.startswith('firefox') and '+arm64' not in version:   # Mint's own Firefox builds are amd64
        continue
    if arch != 'all' or '+arm64' in version:   # rebuilt here, or made for this arm64 build
        chosen.append(path)
        continue
    ubuntu = ubuntu_version(name)
    if ubuntu and apt_pkg.version_compare(ubuntu, version) > 0:
        chosen.append(path)
    elif os.path.getsize(path) <= limit and (source in rebuilt_sources or installed(name) or name in mint_main
                                             or name in in_manifest):
        chosen.append(path)

for path in chosen:
    dest = os.path.join(out_dir, os.path.basename(os.path.dirname(path)))
    os.makedirs(dest, exist_ok=True)
    shutil.copy2(path, dest)
print(f'{len(chosen)} packages, {sum(os.path.getsize(p) for p in chosen) / 1e6:.1f} MB')
