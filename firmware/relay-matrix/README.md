# Relay LED matrix

The animation on the UNO Q's 13x8 LED matrix (8 brightness levels): waves, then `</>` sinks into the flood, the ark rises from it, its three windows light up one by one as people come aboard, and a dove crosses when the rain stops. About 14 seconds, looping.

`frames.py` draws every frame from a few small pictures (the ark, the glyphs, the wave pattern) and writes `sketch/frames.h`. Change the pictures there, not the header.

```sh
python3 frames.py --preview /tmp/ark-matrix.gif   # regenerate, and a GIF to check it
```

Install it on the UNO Q as an App that starts at boot (the `TMPDIR` is needed under `adb shell`, which sets an Android temp path):

```sh
adb shell 'export TMPDIR=/tmp; arduino-app-cli app new ark-logo'
adb push sketch/sketch.ino sketch/frames.h /home/arduino/ArduinoApps/ark-logo/sketch/
adb shell 'export TMPDIR=/tmp; arduino-app-cli app start user:ark-logo && arduino-app-cli properties set default user:ark-logo'
```

The relay hub (`relay/hub.py`) runs separately on the Linux side and isn't affected.
