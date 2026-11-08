# Relay hub (Arduino UNO Q)

`hub.py` runs on the UNO Q's Linux side. Stations connect to it over TCP on port 4210, and every line one station sends goes to all the others.

## Install

```sh
adb devices                                  # note the UNO Q's serial
adb -s SERIAL shell mkdir -p /home/arduino/ark
adb -s SERIAL push relay/hub.py /home/arduino/ark/hub.py
adb -s SERIAL shell 'cd /home/arduino/ark && (setsid nohup python3 hub.py > hub.log 2>&1 &)'
```

Don't stop it with `pkill -f ark/hub.py` from `adb shell`. That pattern also matches the adb shell's own command line, so it kills the shell too. Use `pkill -f "^python3 hub.py"`.

## Connecting a station

Over USB:

```sh
adb -s SERIAL forward tcp:4210 tcp:4210
socat pty,raw,echo=0,link=/tmp/ark-a TCP:127.0.0.1:4210
```

Over Wi-Fi, with the UNO Q's address:

```sh
socat pty,raw,echo=0,link=/tmp/ark-b TCP:UNOQ_IP:4210
```

The station then opens `/tmp/ark-a` or `/tmp/ark-b` as its serial port.

## Wi-Fi

While developing, the UNO Q joins the same Wi-Fi as the laptop:

```sh
adb -s SERIAL shell nmcli dev wifi connect SSID password PASSWORD
```

For the demo it joins a network the team controls (a phone hotspot works), never the company's. Running its own access point would remove even that, but it isn't set up.

## Without the UNO Q

The hub is plain Python 3 with no dependencies, so it also runs on a laptop:

```sh
python3 relay/hub.py
./station.sh station-a wifi 127.0.0.1
./station.sh station-b wifi 127.0.0.1
```

It listens on port 4210 on every interface. Stations on other laptops can use the laptop's address instead of 127.0.0.1.
