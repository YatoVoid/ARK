# Attack simulation (demo prop)

> **Disclaimer: this is a demo prop, not part of ARK.**
> It is not connected to or integrated with ARK in any way. It only plays the attacker's
> side of our presentation on screen. **It doesn't attack anything.** Every command and
> result is scripted text, and every name is made up.

## What it is

This is the "attacker's screen" from our ARK presentation. It plays like a movie: press
Enter and the next attack step types itself out.

The one real part is the upload at the end. While it runs, the script checks whether this
laptop is still online. When the manager presses ARK's **red button** and this laptop loses
its network, the upload freezes for real: `CONNECTION LOST`. When the network comes back after
the **green button**, the attacker's logins fail: `ACCESS DENIED`.

**Made-up names:** the victim company is **Meridian** (`meridian.example`; the `.example`
domain is reserved and can never be a real company). The employee is Maya Ortiz, the attack
group is GRAYHOUND, and the IP addresses (`203.0.113.x`) are reserved for documentation.

## Run it

Python 3 only. Nothing to install. On Windows use `python`; on Mac or Linux use `python3`.

```bash
python hacker.py --check     # should say REACHABLE (this laptop is online)
python hacker.py             # start the show
```

Make the terminal full-screen and zoom in (Ctrl + plus) so people can read it.

## Keys

| Key | What it does |
|---|---|
| **Enter** | Next step |
| **F** | Freeze the upload now (backup if the network doesn't drop) |
| **G** | Play the "access denied" ending now (backup if the network doesn't come back) |
| **R** | Reset to the start |
| **Q** | Quit |

## Cue sheet: matching ARK alerts

The analyst's ARK screen shows a "server-room sensor" alert after each attacker step. These
alerts are **dummy data inside ARK**, triggered by hand. Show each one **right after** the
attacker's step finishes on screen.

| # | Attacker screen (this script) | ARK alert to show on the analyst's screen | MITRE ATT&CK |
|---|---|---|---|
| 1 | Phishing email sent, `credentials captured: m.ortiz` | — (nothing yet, the attacker is quiet) | T1566.002 |
| 2 | `vpn-login --user m.ortiz`: session opened on FIN-LAPTOP-07 | `WARN  New login m.ortiz from unfamiliar IP 203.0.113.47 (FIN-LAPTOP-07)` | T1078 |
| 3 | `vssadmin delete shadows`: 14 shadow copies deleted | `CRIT  Backup deletion: vssadmin delete shadows on FIN-LAPTOP-07` | T1490 |
| 4 | `wevtutil cl Security`: Security log cleared | `CRIT  Security event log cleared on FIN-LAPTOP-07` | T1070.001 |
| 5 | Finance share encrypted, 1,284 files | `CRIT  Mass file encryption: 1,284 files *.locked on FS-01\Finance` | T1486 |
| 6 | HR-DB upload starts climbing | `CRIT  Large upload HR-DB -> 203.0.113.88 (in progress)` | T1567 |
| — | **Analyst tells the manager in ARK chat. Manager presses RED.** Upload freezes: `CONNECTION LOST` | Incident declared, company network isolated | — |
| — | **Team works the incident in ARK. Manager presses GREEN.** Network back: `ACCESS DENIED`, session terminated | Incident resolved | — |

The IPs match the attacker's banner: `203.0.113.47` is the attacker's machine and
`203.0.113.88` is where the stolen data goes.

## Options

| Option | Default | Use it when |
|---|---|---|
| `--speed 3.5` | 3.5 | The upload is too fast or slow. At 3.5 it reaches about 55–65% 15–20 seconds after it starts. |
| `--target tcp://8.8.8.8:53` | `tcp://1.1.1.1:443` | The Wi-Fi blocks the default address, so `--check` says UNREACHABLE while you're online |

To rename the made-up company, change the `DOMAIN` line near the top of `hacker.py`.
