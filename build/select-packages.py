#!/usr/bin/python3
"""Turn the original Linux Mint manifest plus packages.conf into the arm64 install list.

usage: select-packages.py MANIFEST PACKAGES_CONF ROOTS AVAILABLE INSTALL_OUT MANUAL_OUT
  AVAILABLE   package names the arm64 chroot's apt can install (apt-cache pkgnames)
  INSTALL_OUT packages to install
  MANUAL_OUT  packages to mark as manually installed (everything else becomes automatic,
              so packages only needed by dropped applications are autoremoved)
"""
import collections
import fnmatch
import sys

manifest, conf_path, roots_path, avail_path, install_out, manual_out = sys.argv[1:7]

conf = collections.defaultdict(list)
section = None
for line in open(conf_path):
    line = line.split('#')[0].strip()
    if not line:
        continue
    if line.startswith('['):
        section = line.strip('[]')
        continue
    conf[section] += line.split()

drops = conf['drop-x86'] + conf['drop-vm'] + conf['drop-light']

def dropped(name):
    return any(fnmatch.fnmatchcase(name, pattern) for pattern in drops)

names = [line.split()[0].split(':')[0] for line in open(manifest) if line.strip()]
available = {line.strip() for line in open(avail_path) if line.strip()}
roots = [line.strip() for line in open(roots_path) if line.strip() and not line.startswith('#')]

wanted = [n for n in names if not dropped(n)] + conf['keep'] + conf['add']
install = sorted({n for n in wanted if n in available})
missing = sorted({n for n in wanted if n not in available})
manual = sorted({n for n in roots + conf['keep'] + conf['add'] if n in available and not dropped(n)})

open(install_out, 'w').write('\n'.join(install) + '\n')
open(manual_out, 'w').write('\n'.join(manual) + '\n')
print(f'install {len(install)}  manual {len(manual)}  not available on arm64: {len(missing)}')
if missing:
    print('  ' + ' '.join(missing))
