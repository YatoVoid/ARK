#!/usr/bin/env python3
"""ARK relay hub, run on the Arduino UNO Q.

Stations connect over TCP, one over USB through an adb port forward and the
rest over Wi-Fi, and every line one station sends is passed to all the
others. The hub never sees a key. Lines are sealed and signed by the
stations, so a tampered hub can drop or inject lines but can't read or
forge them.

Line format: "M <hex>\n", at most 2 * 250 + 8 bytes. Anything longer is
dropped.
"""

import selectors
import socket
import time

PORT = 4210
MAX_LINE = 2 * 250 + 8
MAX_STATIONS = 8

sel = selectors.DefaultSelector()
pending = {}  # socket -> bytes of an unfinished line


def say(text):
    print(time.strftime("%H:%M:%S"), text, flush=True)


def drop(sock):
    sel.unregister(sock)
    pending.pop(sock, None)
    try:
        say(f"left    {sock.getpeername()[0]}  ({len(pending)} connected)")
    except OSError:
        say(f"left    ({len(pending)} connected)")
    sock.close()


def accept(server):
    sock, addr = server.accept()
    if len(pending) >= MAX_STATIONS:
        sock.close()
        return
    sock.settimeout(1.0)
    pending[sock] = b""
    sel.register(sock, selectors.EVENT_READ)
    say(f"joined  {addr[0]}  ({len(pending)} connected)")


def forward(sender, line):
    for sock in list(pending):
        if sock is sender:
            continue
        try:
            sock.sendall(line + b"\n")
        except OSError:
            drop(sock)


def read(sock):
    try:
        data = sock.recv(4096)
    except OSError:
        data = b""
    if not data:
        drop(sock)
        return
    buf = pending[sock] + data
    *lines, rest = buf.split(b"\n")
    for line in lines:
        line = line.rstrip(b"\r")
        if line.startswith(b"M ") and len(line) <= MAX_LINE:
            forward(sock, line)
    pending[sock] = rest if len(rest) <= MAX_LINE else b""


def main():
    server = socket.socket()
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("0.0.0.0", PORT))
    server.listen()
    sel.register(server, selectors.EVENT_READ)
    say(f"ARK hub listening on port {PORT}")
    while True:
        for key, _ in sel.select():
            if key.fileobj is server:
                accept(server)
            else:
                read(key.fileobj)


if __name__ == "__main__":
    main()
