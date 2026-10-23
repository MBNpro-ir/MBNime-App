# Android compatibility media

`mbn-compatibility.mp4` is a synthetic 30-second test pattern and 440 Hz tone.
The Android 6 and Android TV workflows serve this local fixture so emulator
tests do not depend on downloading FFmpeg and its system packages at runtime.
It is not an application asset and is not bundled in releases.

To regenerate it from this directory with FFmpeg:

```sh
ffmpeg -hide_banner -loglevel error -nostdin -y \
  -f lavfi -i testsrc2=size=320x180:rate=24 \
  -f lavfi -i sine=frequency=440:sample_rate=44100 \
  -t 30 -c:v libx264 -profile:v baseline -pix_fmt yuv420p \
  -c:a aac -b:a 64k -movflags +faststart mbn-compatibility.mp4
```
