#!/usr/bin/python3
"""Write a raw disk image as a compressed qcow2 (version 3, zstd), as
`qemu-img convert -c -O qcow2 -o compression_type=zstd` does, but with each 64 KiB cluster
compressed at another zstd level than QEMU's fixed 3. Measured on the ready-made VM's disk:
level 12 makes it 4.5 % smaller and decompresses about 6 % faster (levels 6 to 12 decompress
faster than 3; 15 and above are smaller still but decompress more slowly). All-zero clusters
are left unallocated, as qemu-img does; a cluster that does not compress is stored as it is.
Check the result with `qemu-img check` and `qemu-img compare RAW QCOW2` (30-image.sh does both).

usage: qcow2-zstd.py [--level N] RAW QCOW2
"""
import argparse
import multiprocessing
import os
import struct

import zstandard

CLUSTER_BITS = 16
CLUSTER = 1 << CLUSTER_BITS
L2_ENTRIES = CLUSTER // 8           # 8-byte entries per L2 table
REFCOUNT_ORDER = 4                  # 16-bit refcounts
REFS_PER_BLOCK = CLUSTER // 2
CSIZE_SHIFT = 62 - (CLUSTER_BITS - 8)
COMPRESSED = 1 << 62
COPIED = 1 << 63
BATCH = 256                         # clusters per job


def data_clusters(path, size):
    """Indices of the clusters that hold data, from the file's allocated extents."""
    fd = os.open(path, os.O_RDONLY)
    try:
        pos = 0
        while pos < size:
            try:
                start = os.lseek(fd, pos, os.SEEK_DATA)
            except OSError:      # no data after pos
                return
            end = os.lseek(fd, start, os.SEEK_HOLE)
            yield from range(start // CLUSTER, (end + CLUSTER - 1) // CLUSTER)
            pos = end
    finally:
        os.close(fd)


def compress_batch(job):
    path, level, indices = job
    zc = zstandard.ZstdCompressor(level=level, write_content_size=True)
    out = []
    with open(path, 'rb') as f:
        for i in indices:
            f.seek(i * CLUSTER)
            data = f.read(CLUSTER).ljust(CLUSTER, b'\0')
            if not data.strip(b'\0'):
                continue                                 # stays unallocated: reads as zeros
            blob = zc.compress(data)
            out.append((i, blob) if len(blob) < CLUSTER - 512 else (i, None, data))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--level', type=int, default=12)
    ap.add_argument('raw')
    ap.add_argument('qcow2')
    a = ap.parse_args()
    size = os.path.getsize(a.raw)
    if size % 512:
        raise SystemExit('the raw image size is not a multiple of 512 bytes')

    # compress every cluster that holds data, in parallel, in cluster order
    seen, ordered = set(), []
    for i in data_clusters(a.raw, size):
        if i not in seen:
            seen.add(i)
            ordered.append(i)
    jobs = [(a.raw, a.level, ordered[k:k + BATCH]) for k in range(0, len(ordered), BATCH)]
    clusters = []                                        # (index, compressed blob or None, raw data)
    with multiprocessing.Pool() as pool:
        for batch in pool.imap(compress_batch, jobs, chunksize=4):
            clusters.extend(batch)

    # layout: header, refcount table, L1 table, L2 tables, data, refcount blocks
    n_clusters = (size + CLUSTER - 1) // CLUSTER
    l1_size = (n_clusters + L2_ENTRIES - 1) // L2_ENTRIES
    l1_clusters = (l1_size * 8 + CLUSTER - 1) // CLUSTER
    reftable_off, l1_off = CLUSTER, 2 * CLUSTER
    l2_indices = sorted({c[0] // L2_ENTRIES for c in clusters})
    l2_off = {j: (2 + l1_clusters + k) * CLUSTER for k, j in enumerate(l2_indices)}
    pos = (2 + l1_clusters + len(l2_indices)) * CLUSTER
    data_start = pos
    placed = []                                          # (index, offset, bytes, compressed)
    for c in clusters:
        if c[1] is not None:
            placed.append((c[0], pos, c[1], True))
            pos += len(c[1])
        else:
            pos = (pos + CLUSTER - 1) // CLUSTER * CLUSTER
            placed.append((c[0], pos, c[2], False))
            pos += CLUSTER
    data_end = pos
    refblocks_off = (data_end + 511) // 512 * 512        # the last compressed sector is whole
    refblocks_off = (refblocks_off + CLUSTER - 1) // CLUSTER * CLUSTER
    n_rb = 1
    while (refblocks_off // CLUSTER + n_rb) > n_rb * REFS_PER_BLOCK:
        n_rb += 1
    total = refblocks_off // CLUSTER + n_rb
    if n_rb > CLUSTER // 8:
        raise SystemExit('image too large for one refcount table cluster')

    # refcounts: one per metadata cluster, one per compressed cluster touching a host cluster
    refs = [0] * total
    for h in range(2 + l1_clusters + len(l2_indices)):
        refs[h] = 1
    l2 = {j: [0] * L2_ENTRIES for j in l2_indices}
    for i, off, blob, compressed in placed:
        if compressed:
            extra = ((off + len(blob) - 1) >> 9) - (off >> 9)
            l2[i // L2_ENTRIES][i % L2_ENTRIES] = COMPRESSED | (extra << CSIZE_SHIFT) | off
            for h in range(off >> CLUSTER_BITS, ((off + len(blob) - 1) >> CLUSTER_BITS) + 1):
                refs[h] += 1
        else:
            l2[i // L2_ENTRIES][i % L2_ENTRIES] = COPIED | off
            refs[off >> CLUSTER_BITS] += 1
    for k in range(n_rb):
        refs[refblocks_off // CLUSTER + k] = 1
    if max(refs) >= 1 << 16:
        raise SystemExit('a refcount overflows 16 bits')

    header = struct.pack('>4sIQIIQIIQQIIQQQQII', b'QFI\xfb', 3, 0, 0, CLUSTER_BITS, size, 0,
                         l1_size, l1_off, reftable_off, 1, 0, 0,
                         1 << 3,          # incompatible: the compression type is not zlib
                         0, 0, REFCOUNT_ORDER, 112)
    header += bytes([1]) + bytes(7)                      # compression type 1: zstd
    header += struct.pack('>II', 0, 0)                   # end of header extensions
    reftable = b''.join(struct.pack('>Q', refblocks_off + k * CLUSTER) for k in range(n_rb))
    l1 = b''.join(struct.pack('>Q', COPIED | l2_off[j] if j in l2_off else 0) for j in range(l1_size))

    with open(a.qcow2 + '.part', 'wb') as f:
        f.write(header.ljust(CLUSTER, b'\0'))
        f.write(reftable.ljust(CLUSTER, b'\0'))
        f.write(l1.ljust(l1_clusters * CLUSTER, b'\0'))
        for j in l2_indices:
            f.write(b''.join(struct.pack('>Q', e) for e in l2[j]))
        assert f.tell() == data_start
        for i, off, blob, compressed in placed:
            if f.tell() < off:
                f.write(bytes(off - f.tell()))
            f.write(blob)
        f.write(bytes(refblocks_off - f.tell()))
        for k in range(n_rb):
            block = refs[k * REFS_PER_BLOCK:(k + 1) * REFS_PER_BLOCK]
            f.write(struct.pack(f'>{len(block)}H', *block).ljust(CLUSTER, b'\0'))
    os.replace(a.qcow2 + '.part', a.qcow2)
    stored = sum(len(p[2]) for p in placed)
    print(f'{len(placed)} clusters with data ({sum(1 for p in placed if not p[3])} stored as they are), '
          f'{stored / 1e6:,.0f} MB of data, {os.path.getsize(a.qcow2) / 1e6:,.0f} MB file')


if __name__ == '__main__':
    main()
