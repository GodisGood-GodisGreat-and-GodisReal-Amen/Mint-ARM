#!/usr/bin/python3
"""Talk to a test VM through the QEMU guest agent (a TCP chardev, see testvm.sh).

usage: qga.py PORT ping                        wait until the agent answers
       qga.py PORT run 'shell command' [SECS]  run as root in the guest; prints its output,
                                               exits with its status (default timeout 120 s)
       qga.py PORT get GUEST_PATH LOCAL_PATH   copy a file out of the guest
       qga.py PORT put LOCAL_PATH GUEST_PATH   copy a file into the guest
"""
import base64
import json
import socket
import sys
import time

CHUNK = 4 << 20


class Agent:
    def __init__(self, port, timeout=30):
        self.sock = socket.create_connection(('127.0.0.1', int(port)), timeout=timeout)
        self.f = self.sock.makefile('rw')
        # The agent may still hold replies meant for an earlier client: resynchronise first.
        token = int(time.time() * 1000) & 0x7fffffff
        self.send('guest-sync', id=token)
        while True:
            line = self.f.readline()
            if not line:
                raise ConnectionError('the guest agent closed the connection')
            if line.strip() and json.loads(line).get('return') == token:
                break

    def send(self, name, **args):
        self.f.write(json.dumps({'execute': name, 'arguments': args} if args else {'execute': name}) + '\n')
        self.f.flush()

    def call(self, name, **args):
        self.send(name, **args)
        while True:
            line = self.f.readline()
            if not line:
                raise ConnectionError('the guest agent closed the connection')
            reply = json.loads(line)
            if 'error' in reply:
                raise RuntimeError(f"{name}: {reply['error'].get('desc', reply['error'])}")
            if 'return' in reply:
                return reply['return']


def run(agent, command, timeout):
    agent.sock.settimeout(timeout + 30)
    pid = agent.call('guest-exec', path='/bin/bash', arg=['-c', command], **{'capture-output': True})['pid']
    deadline = time.time() + timeout
    while True:
        status = agent.call('guest-exec-status', pid=pid)
        if status.get('exited'):
            break
        if time.time() > deadline:
            sys.exit(f'timed out after {timeout:.0f} s')
        time.sleep(0.25)
    sys.stdout.write(base64.b64decode(status.get('out-data', '')).decode(errors='replace'))
    sys.stderr.write(base64.b64decode(status.get('err-data', '')).decode(errors='replace'))
    return status.get('exitcode', 0)


def get(agent, remote, local):
    agent.sock.settimeout(300)
    handle = agent.call('guest-file-open', path=remote, mode='rb')
    with open(local, 'wb') as out:
        while True:
            part = agent.call('guest-file-read', handle=handle, count=CHUNK)
            out.write(base64.b64decode(part['buf-b64']))
            if part['eof'] or not part['count']:
                break
    agent.call('guest-file-close', handle=handle)


def put(agent, local, remote):
    agent.sock.settimeout(300)
    handle = agent.call('guest-file-open', path=remote, mode='wb')
    with open(local, 'rb') as src:
        while block := src.read(CHUNK):
            agent.call('guest-file-write', handle=handle, **{'buf-b64': base64.b64encode(block).decode()})
    agent.call('guest-file-close', handle=handle)


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    port, op, args = sys.argv[1], sys.argv[2], sys.argv[3:]
    if op == 'ping':
        deadline = time.time() + float(args[0] if args else 300)
        while True:
            try:
                Agent(port, timeout=5).call('guest-ping')
                return
            except (OSError, ConnectionError, ValueError):
                if time.time() > deadline:
                    sys.exit('no answer from the guest agent')
                time.sleep(2)
    try:
        agent = Agent(port)
        if op == 'run':
            sys.exit(run(agent, args[0], float(args[1]) if len(args) > 1 else 120))
        elif op == 'get':
            get(agent, args[0], args[1])
        elif op == 'put':
            put(agent, args[0], args[1])
        else:
            sys.exit(__doc__)
    except (OSError, ConnectionError) as error:
        # also what happens when the command restarts or stops the guest
        sys.exit(f'the guest agent stopped answering ({error or type(error).__name__})')


if __name__ == '__main__':
    main()
