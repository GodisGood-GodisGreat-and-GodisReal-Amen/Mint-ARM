#!/usr/bin/python3
"""Drive a headless test VM over QMP (see testvm.sh): screenshots, keys, clicks.

usage: qmp.py PORT shot OUT.png            screenshot of the VM's display (PNG)
       qmp.py PORT keys KEY [KEY ...]      press keys: 'ret', 'tab', 'ctrl-alt-t' style chords,
                                           'text:Hello world' types text (US layout)
       qmp.py PORT click X Y [W H]         left click at X,Y on a W x H screen (default 1920x1080)
       qmp.py PORT cmd '{"name": ...}'     any QMP command, e.g. '{"name": "quit"}'
"""
import json
import socket
import sys
import time

SHIFTED = {'!': '1', '@': '2', '#': '3', '$': '4', '%': '5', '^': '6', '&': '7', '*': '8',
           '(': '9', ')': '0', '_': 'minus', '+': 'equal', '{': 'bracket_left', '}': 'bracket_right',
           '|': 'backslash', ':': 'semicolon', '"': 'apostrophe', '<': 'comma', '>': 'dot', '?': 'slash',
           '~': 'grave_accent'}
PLAIN = {' ': 'spc', '-': 'minus', '=': 'equal', '[': 'bracket_left', ']': 'bracket_right',
         '\\': 'backslash', ';': 'semicolon', "'": 'apostrophe', ',': 'comma', '.': 'dot', '/': 'slash',
         '`': 'grave_accent', '\n': 'ret', '\t': 'tab'}
ALIASES = {'enter': 'ret', 'return': 'ret', 'space': 'spc', 'escape': 'esc', 'super': 'meta_l',
           'win': 'meta_l', 'del': 'delete'}


class QMP:
    def __init__(self, port):
        self.sock = socket.create_connection(('127.0.0.1', int(port)), timeout=60)
        self.f = self.sock.makefile('rw')
        json.loads(self.f.readline())   # the greeting
        self.cmd('qmp_capabilities')

    def cmd(self, name, **args):
        self.f.write(json.dumps({'execute': name, 'arguments': args} if args else {'execute': name}) + '\n')
        self.f.flush()
        while True:
            reply = json.loads(self.f.readline())
            if 'error' in reply:
                raise RuntimeError(f"{name}: {reply['error'].get('desc', reply['error'])}")
            if 'return' in reply:
                return reply['return']

    def chord(self, qcodes):
        def events(codes, down):
            return [{'type': 'key', 'data': {'down': down, 'key': {'type': 'qcode', 'data': q}}} for q in codes]
        self.cmd('input-send-event', events=events(qcodes, True))
        time.sleep(0.04)
        self.cmd('input-send-event', events=events(list(reversed(qcodes)), False))
        time.sleep(0.04)

    def text(self, s):
        for ch in s:
            if ch.isascii() and ch.isalpha():
                self.chord(['shift', ch.lower()] if ch.isupper() else [ch])
            elif ch.isdigit():
                self.chord([ch])
            elif ch in PLAIN:
                self.chord([PLAIN[ch]])
            elif ch in SHIFTED:
                self.chord(['shift', SHIFTED[ch]])
            else:
                raise ValueError(f'cannot type {ch!r}')

    def click(self, x, y, w=1920, h=1080):
        ax, ay = round(x * 32767 / (w - 1)), round(y * 32767 / (h - 1))
        self.cmd('input-send-event', events=[{'type': 'abs', 'data': {'axis': 'x', 'value': ax}},
                                             {'type': 'abs', 'data': {'axis': 'y', 'value': ay}}])
        time.sleep(0.05)
        for down in (True, False):
            self.cmd('input-send-event', events=[{'type': 'btn', 'data': {'down': down, 'button': 'left'}}])
            time.sleep(0.05)


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    qmp, op, args = QMP(sys.argv[1]), sys.argv[2], sys.argv[3:]
    if op == 'shot':
        qmp.cmd('screendump', filename=args[0], format='png')
    elif op == 'keys':
        for key in args:
            if key.startswith('text:'):
                qmp.text(key[5:])
            else:
                qmp.chord([ALIASES.get(part, part) for part in key.split('-')])
    elif op == 'click':
        qmp.click(*map(int, args[:4]))
    elif op == 'cmd':
        request = json.loads(args[0])
        print(json.dumps(qmp.cmd(request.pop('name'), **request), indent=1))
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
