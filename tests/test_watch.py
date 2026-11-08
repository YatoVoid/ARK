"""Checks tools/ark-watch turns journal and access-log lines into events."""
import importlib.machinery
import importlib.util
import os
import sys

sys.dont_write_bytecode = True
import tempfile

here = os.path.dirname(os.path.abspath(__file__))
loader = importlib.machinery.SourceFileLoader("ark_watch", os.path.join(here, "..", "tools", "ark-watch"))
spec = importlib.util.spec_from_loader("ark_watch", loader)
w = importlib.util.module_from_spec(spec)
loader.exec_module(w)

failed = 0


def check(got, want, what):
    global failed
    if got != want:
        failed += 1
        print("FAIL %s: got %r, want %r" % (what, got, want))


def j(ident, msg, uid="1000"):
    return w.from_journal({"SYSLOG_IDENTIFIER": ident, "MESSAGE": msg, "_UID": uid})


check(j("ark-shell", "cat /etc/shadow", "0"), ("shell", "root", "cat /etc/shadow"), "shell command")
check(j("sudo", "wali : TTY=pts/3 ; PWD=/home/wali ; USER=root ; COMMAND=/usr/bin/systemctl stop nginx"),
      ("sudo", "wali", "/usr/bin/systemctl stop nginx"), "sudo command")
check(j("sudo", "wali : 3 incorrect password attempts ; TTY=pts/3 ; PWD=/ ; USER=root ; COMMAND=/bin/sh"),
      ("fail", "wali", "wrong sudo password"), "sudo wrong password")
check(j("sudo", "pam_unix(sudo:session): session opened for user root(uid=0) by wali(uid=1000)"), None,
      "sudo session noise skipped")
check(j("sshd-session", "Accepted publickey for marcus from 10.0.4.22 port 50122 ssh2: ED25519 SHA256:x"),
      ("login", "marcus", "ssh from 10.0.4.22"), "ssh login")
check(j("sshd", "Failed password for invalid user admin from 185.220.101.7 port 4242 ssh2"),
      ("fail", "admin", "ssh password from 185.220.101.7"), "ssh failed, invalid user")
check(j("sshd", "Failed password for root from 185.220.101.7 port 4242 ssh2"),
      ("fail", "root", "ssh password from 185.220.101.7"), "ssh failed")
check(j("su", "FAILED SU (to root) wali on pts/2"), ("fail", "wali", "su to root"), "su failed")
check(j("su", "(to root) wali on pts/2"), ("login", "wali", "su to root"), "su ok")
check(j("useradd", "new user: name=bob, UID=1001, GID=1001, home=/home/bob, shell=/bin/bash", "0"),
      ("account", "root", "useradd: new user: name=bob, UID=1001, GID=1001, home=/home/bob, shell=/bin/bash"),
      "useradd")
check(w.from_access('185.220.101.7 - - [07/Nov/2026:21:06:01 +0000] "GET /.env HTTP/1.1" 404 153 "-" "curl/8"'),
      ("request", "-", "GET /.env 404 from 185.220.101.7"), "access log")
check(w.from_access("garbage"), None, "bad access line skipped")
check(w.clean("a\tb\nc\x1b[31m", 100), "a b c [31m", "control characters removed")

with tempfile.TemporaryDirectory() as d:
    feed = w.Feed(os.path.join(d, "feed"), False)
    feed.write("fs-01", ("shell", "eve\tx", "rm -rf /srv\nnext"))
    with open(os.path.join(d, "feed")) as f:
        check(f.read(), "shell\teve x\tfs-01\trm -rf /srv next\n", "feed line has exactly four fields")
    check(oct(os.stat(os.path.join(d, "feed")).st_mode & 0o777), "0o600", "feed is private")

print("test_watch: %s" % ("FAILED" if failed else "all passed"))
sys.exit(1 if failed else 0)
