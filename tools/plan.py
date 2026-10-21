#!/usr/bin/python3
"""Work out what the build needs from a Linux Mint release: the Linux Mint source packages to
rebuild for arm64, in build layers (LAYERS in build/10-packages.sh), and the top-level packages
of the ISO's selection that the build keeps (build/roots.txt). Needed when moving the build to
a newer Linux Mint.

usage: plan.py fetch INDEX_DIR [MINT_SUITE] [UBUNTU_SUITE]
         download the package indexes: Linux Mint's (amd64 and sources) from packages.linuxmint.com
         and Ubuntu's arm64 ones from ports.ubuntu.com (default suites: zena, noble)
       plan.py plan INDEX_DIR MANIFEST PACKAGES_CONF [ROOTS_OUT]
         MANIFEST is casper/filesystem.manifest from Linux Mint's x86 ISO, for example
         bsdtar -xOf linuxmint-22.3-cinnamon-64bit.iso casper/filesystem.manifest
"""
import collections
import fnmatch
import gzip
import os
import re
import sys
import urllib.request

MINT_URL = 'http://packages.linuxmint.com'
UBUNTU_URL = 'http://ports.ubuntu.com/ubuntu-ports'
MINT_COMPONENTS = ['main', 'upstream', 'import', 'backport']
UBUNTU_COMPONENTS = ['main', 'restricted', 'universe', 'multiverse']
# Firefox comes from Mozilla's arm64 repository instead, and Thunderbird is not in the image.
NOT_REBUILT = {'firefox', 'thunderbird'}
NAME = re.compile(r'(?:^|[,|]\s*)([a-z0-9][a-z0-9+.\-]+)')


def fetch(index_dir, mint_suite='zena', ubuntu_suite='noble'):
    def get(url, path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        print('fetching', url)
        urllib.request.urlretrieve(url, path)
    for c in MINT_COMPONENTS:
        get(f'{MINT_URL}/dists/{mint_suite}/{c}/binary-amd64/Packages.gz', f'{index_dir}/mint/{c}-amd64.gz')
        get(f'{MINT_URL}/dists/{mint_suite}/{c}/source/Sources.gz', f'{index_dir}/mint/{c}-src.gz')
    for suite in (ubuntu_suite, f'{ubuntu_suite}-updates', f'{ubuntu_suite}-security', f'{ubuntu_suite}-backports'):
        for c in UBUNTU_COMPONENTS:
            get(f'{UBUNTU_URL}/dists/{suite}/{c}/binary-arm64/Packages.gz', f'{index_dir}/ubuntu/{suite}-{c}-arm64.gz')


def records(path):
    """The stanzas of a Debian control file (gzip-compressed), continuation lines joined."""
    with gzip.open(path, 'rt', encoding='utf-8', errors='replace') as f:
        record, last = {}, None
        for line in f:
            line = line.rstrip('\n')
            if not line:
                if record:
                    yield record
                record, last = {}, None
            elif line[0] in ' \t':
                if last:
                    record[last] += ' ' + line.strip()
            else:
                key, _, value = line.partition(':')
                record[key], last = value.strip(), key
        if record:
            yield record


def names(field):
    return set(NAME.findall(field or ''))


def plan(index_dir, manifest_path, conf_path, roots_out=None):
    manifest = [line.split()[0].split(':')[0] for line in open(manifest_path) if line.strip()]
    in_manifest = set(manifest)

    conf, section = collections.defaultdict(list), None
    for line in open(conf_path):
        line = line.split('#')[0].strip()
        if line.startswith('['):
            section = line.strip('[]')
        elif line:
            conf[section] += line.split()
    drops = conf['drop-x86'] + conf['drop-vm'] + conf['drop-light']

    def dropped(name):
        return any(fnmatch.fnmatchcase(name, pattern) for pattern in drops)

    packages = {}   # Ubuntu first, then Linux Mint's packages over them, as on Linux Mint
    for name in sorted(os.listdir(f'{index_dir}/ubuntu')):
        for r in records(f'{index_dir}/ubuntu/{name}'):
            packages[r['Package']] = r
    mint_binaries, mint_sources = {}, {}
    for c in MINT_COMPONENTS:
        for r in records(f'{index_dir}/mint/{c}-amd64.gz'):
            packages[r['Package']] = mint_binaries[r['Package']] = r
        for r in records(f'{index_dir}/mint/{c}-src.gz'):
            mint_sources[r['Package']] = r

    # The Mint source packages behind the manifest's architecture-specific Mint binaries
    rebuild = sorted({mint_binaries[n].get('Source', n).split()[0] for n in in_manifest
                      if n in mint_binaries and mint_binaries[n]['Architecture'] != 'all'} - NOT_REBUILT)
    missing = [s for s in rebuild if s not in mint_sources]
    if missing:
        sys.exit(f'no source package in the index for: {" ".join(missing)}')

    # Layers: a source goes in the first layer after every source whose binaries it build-depends on
    built_by = {b: s for s in rebuild for b in re.split(r'[,\s]+', mint_sources[s].get('Binary', '')) if b}
    needs = {}
    for s in rebuild:
        fields = ' , '.join(mint_sources[s].get(k, '') for k in ('Build-Depends', 'Build-Depends-Arch', 'Build-Depends-Indep'))
        needs[s] = {built_by[n] for n in names(fields) if built_by.get(n, s) != s}
    layers, done = [], set()
    while len(done) < len(rebuild):
        layer = [s for s in rebuild if s not in done and needs[s] <= done]
        if not layer:
            sys.exit(f'circular build dependencies among: {" ".join(s for s in rebuild if s not in done)}')
        layers.append(layer)
        done.update(layer)

    # Top-level packages, kept marked as manually installed so that everything only they needed
    # can be autoremoved: those no other package of the manifest needs, those in dependency cycles
    # that nothing outside the cycle reaches (selected explicitly too), and the base system
    # (Priority required or important, or Essential), less what packages.conf drops.
    provided_by = collections.defaultdict(set)
    for n, r in packages.items():
        for p in names(r.get('Provides')):
            provided_by[p].add(n)
    deps = {}
    for n in in_manifest:
        r, found = packages.get(n, {}), set()
        for kind in ('Pre-Depends', 'Depends', 'Recommends'):
            for d in names(r.get(kind)):
                found |= ({d} | provided_by[d]) & in_manifest
        found.discard(n)
        deps[n] = found
    reached, stack = set(), [n for n in in_manifest if not any(n in d for d in deps.values())]
    top = set(stack)
    while stack:
        n = stack.pop()
        if n not in reached:
            reached.add(n)
            stack += [d for d in deps[n] if d not in reached]
    base = {n for n in in_manifest if packages.get(n, {}).get('Priority') in ('required', 'important')
            or packages.get(n, {}).get('Essential') == 'yes'}
    roots = sorted(n for n in top | (in_manifest - reached) | base if not dropped(n))

    print(f'{len(rebuild)} Linux Mint source packages to rebuild, in {len(layers)} layers (LAYERS in build/10-packages.sh):')
    print('LAYERS=(')
    for layer in layers:
        print(f'  "{" ".join(layer)}"')
    print(')')
    print(f'{len(roots)} top-level packages kept (build/roots.txt)')
    if roots_out:
        with open(roots_out, 'w') as out:
            out.write('# Top-level packages of the Linux Mint 22.3 Cinnamon ISO selection that this build keeps\n'
                      '# (generated from casper/filesystem.manifest and build/packages.conf by tools/plan.py).\n')
            out.write('\n'.join(roots) + '\n')


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == 'fetch':
        fetch(*sys.argv[2:5])
    elif len(sys.argv) >= 5 and sys.argv[1] == 'plan':
        plan(*sys.argv[2:6])
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
