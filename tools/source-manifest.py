#!/usr/bin/python3
"""List the source package behind every binary package of a Linux Mint ARM system, and where
that source is published. Runs inside the system (make-release.sh runs it in the live ISO),
after `apt-get update`, so that apt knows which archive each installed version came from.

usage: source-manifest.py [--status DPKG_ADMINDIR]... [--debs GLOB]...
         prints: source <TAB> version <TAB> where <TAB> binary packages
         where: Ubuntu, Linux Mint, Mozilla, "Linux Mint, patched here" (the patch is in
         build/patches) or "this project" (made by the build scripts: mint-arm-system,
         mint-arm-repo, the firefox-locale-* transitional packages)
       source-manifest.py --rebuilt ARCHIVE_DIR
         prints NAME=VERSION for each Linux Mint source package that was compiled for arm64 or
         patched, from the local archive's .deb files (/usr/share/mint-arm/repo)
"""
import argparse
import glob
import re
import subprocess

import apt_pkg

OURS = '<mint-arm@localhost>'


def deb_fields(path):
    out = subprocess.run(['dpkg-deb', '-f', path, 'Package', 'Version', 'Source', 'Architecture', 'Maintainer'],
                         capture_output=True, text=True, check=True).stdout
    f = dict(line.split(': ', 1) for line in out.splitlines() if ': ' in line)
    source = f.get('Source', f['Package']).split()
    f['Source'] = source[0]
    f['Source-Version'] = source[1].strip('()') if len(source) > 1 else f['Version']
    return f


def rebuilt(archive):
    specs = set()
    for path in glob.glob(f'{archive}/*/*.deb'):
        f = deb_fields(path)
        if f.get('Maintainer', '').endswith(OURS):
            continue
        if f['Architecture'] != 'all' or '+arm64.' in f['Version']:
            specs.add(f"{f['Source']}={re.sub(r'[+]arm64[.][0-9]+$', '', f['Source-Version'])}")
    print('\n'.join(sorted(specs)))


def origins(cache, name, version):
    if name not in cache:
        return set()
    for ver in cache[name].version_list:
        if ver.ver_str == version:
            return {pf.origin for pf, _ in ver.file_list if pf.origin}
    return set()


def where(cache, binary, version, maintainer):
    if maintainer.endswith(OURS):
        return 'this project'
    if '+arm64.' in version:
        return 'Linux Mint, patched here'
    found = origins(cache, binary, version)
    if 'Linux Mint ARM' in found:
        return 'Linux Mint'
    if 'Ubuntu' in found:
        return 'Ubuntu'
    if found & {'mozilla', 'Mozilla'}:
        return 'Mozilla'
    # Installed from no archive apt knows now: Mint's large artwork packages, which the local
    # archive leaves out, or an Ubuntu version superseded since the build. Linux Mint's and
    # Mozilla's packages name them as maintainers; everything else is Ubuntu's.
    lowered = maintainer.lower()
    if 'linuxmint' in lowered:
        return 'Linux Mint'
    if 'mozilla' in lowered:
        return 'Mozilla'
    return 'Ubuntu'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--status', action='append', default=[], help='a dpkg admin directory')
    parser.add_argument('--debs', action='append', default=[], help='a glob of .deb files')
    parser.add_argument('--rebuilt', metavar='ARCHIVE_DIR', help='list the rebuilt Mint sources instead')
    args = parser.parse_args()
    if args.rebuilt:
        return rebuilt(args.rebuilt)

    apt_pkg.init_config()
    apt_pkg.init_system()
    cache = apt_pkg.Cache(None)
    rows = {}

    def add(binary, version, source, source_version, maintainer):
        row = rows.setdefault((source, source_version), {'where': set(), 'binaries': set()})
        row['where'].add(where(cache, binary, version, maintainer))
        row['binaries'].add(binary)

    for admindir in args.status:
        out = subprocess.run(['dpkg-query', '--admindir', admindir, '-W', '-f',
                              '${db:Status-Abbrev}\t${Package}\t${Version}\t${source:Package}\t'
                              '${source:Version}\t${Maintainer}\n'],
                             capture_output=True, text=True, check=True).stdout
        for line in out.splitlines():
            status, *fields = line.split('\t')
            if status.startswith('ii'):
                add(*fields)
    for pattern in args.debs:
        for path in sorted(glob.glob(pattern, recursive=True)):
            f = deb_fields(path)
            add(f['Package'], f['Version'], f['Source'], f['Source-Version'], f.get('Maintainer', ''))

    for (source, version), row in sorted(rows.items()):
        print('\t'.join([source, version, ' / '.join(sorted(row['where'])), ' '.join(sorted(row['binaries']))]))


if __name__ == '__main__':
    main()
