#!/usr/bin/python3
"""Copy files out of the boot partition of a Linux Mint ARM Raspberry Pi image (FAT32, the first
partition) without mounting it: what testpi.sh needs to start the image's own kernel in QEMU.

usage: pi-boot-files.py IMAGE OUT_DIR [FILE ...]
       IMAGE is the raw .img; FILE names a file in the partition's top folder
       (default: vmlinuz initrd.img cmdline.txt)
"""
import os
import struct
import sys

END_OF_CHAIN = 0x0FFFFFF8


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    image, out = sys.argv[1], sys.argv[2]
    wanted = sys.argv[3:] or ['vmlinuz', 'initrd.img', 'cmdline.txt']
    with open(image, 'rb') as f:
        mbr = f.read(512)
        if mbr[510:512] != b'\x55\xaa':
            sys.exit(f'{image}: no MBR partition table')
        start = struct.unpack_from('<I', mbr, 446 + 8)[0] * 512
        f.seek(start)
        boot = f.read(512)
        sector, per_cluster, reserved, fats = struct.unpack_from('<HBHB', boot, 11)
        if struct.unpack_from('<H', boot, 22)[0] != 0:
            sys.exit(f'{image}: the first partition is not FAT32')
        fat_sectors, root = struct.unpack_from('<I', boot, 36)[0], struct.unpack_from('<I', boot, 44)[0]
        fat = start + reserved * sector
        data = start + (reserved + fats * fat_sectors) * sector
        cluster_size = per_cluster * sector

        def read(cluster, size=None):
            out = bytearray()
            while 2 <= cluster < END_OF_CHAIN and (size is None or len(out) < size):
                f.seek(data + (cluster - 2) * cluster_size)
                out += f.read(cluster_size)
                f.seek(fat + 4 * cluster)
                cluster = struct.unpack('<I', f.read(4))[0] & 0x0FFFFFFF
            return bytes(out if size is None else out[:size])

        files = {}
        directory = read(root)
        for i in range(0, len(directory), 32):
            entry = directory[i:i + 32]
            if entry[0] == 0:
                break
            if entry[0] == 0xE5 or entry[11] & 0x18:   # deleted, long-name part, label or folder
                continue
            base = entry[0:8].decode('ascii', 'replace').rstrip()
            ext = entry[8:11].decode('ascii', 'replace').rstrip()
            cluster = struct.unpack_from('<H', entry, 20)[0] << 16 | struct.unpack_from('<H', entry, 26)[0]
            files[(base + '.' + ext if ext else base).lower()] = (cluster, struct.unpack_from('<I', entry, 28)[0])
        os.makedirs(out, exist_ok=True)
        for name in wanted:
            if name.lower() not in files:
                sys.exit(f'{image}: no {name} in the boot partition')
            cluster, size = files[name.lower()]
            with open(os.path.join(out, name), 'wb') as target:
                target.write(read(cluster, size))


if __name__ == '__main__':
    main()
