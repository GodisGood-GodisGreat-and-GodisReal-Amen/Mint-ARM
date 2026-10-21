#!/usr/bin/python3
"""Write the smallest x86-64 Linux program that prints a line: a static ELF of 194 bytes, two
system calls and no libraries. Running it in an ARM64 VM shows whether Rosetta translates
x86-64 programs there (see vzvm.sh).

usage: x86-hello.py OUT_FILE
"""
import os
import struct
import sys

MESSAGE = b'hello from x86-64, translated by Rosetta\n'
BASE = 0x400000                 # load address
CODE = 64 + 56                  # the code follows the ELF header and one program header


def program():
    code = bytearray()
    code += b'\xb8\x01\x00\x00\x00'                       # mov eax, 1         write(
    code += b'\xbf\x01\x00\x00\x00'                       # mov edi, 1           stdout,
    lea = len(code)
    code += b'\x48\x8d\x35\x00\x00\x00\x00'               # lea rsi, [rip+x]     the message,
    code += b'\xba' + struct.pack('<I', len(MESSAGE))     # mov edx, length      its length)
    code += b'\x0f\x05'                                   # syscall
    code += b'\xb8\x3c\x00\x00\x00'                       # mov eax, 60        exit(
    code += b'\x31\xff'                                   # xor edi, edi         0)
    code += b'\x0f\x05'                                   # syscall
    code[lea + 3:lea + 7] = struct.pack('<i', len(code) - (lea + 7))
    body = bytes(code) + MESSAGE
    size = CODE + len(body)
    elf_header = struct.pack('<4sBBBBB7xHHIQQQIHHHHHH', b'\x7fELF', 2, 1, 1, 0, 0,   # 64-bit, little-endian
                             2, 0x3e, 1, BASE + CODE, 64, 0, 0, 64, 56, 1, 0, 0, 0)  # executable, x86-64
    program_header = struct.pack('<IIQQQQQQ', 1, 5, 0, BASE, BASE, size, size, 0x1000)  # load, read + execute
    return elf_header + program_header + body


if len(sys.argv) != 2:
    sys.exit(__doc__)
with open(sys.argv[1], 'wb') as out:
    out.write(program())
os.chmod(sys.argv[1], 0o755)
