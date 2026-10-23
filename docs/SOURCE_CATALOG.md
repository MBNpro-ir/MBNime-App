# Direct source episode catalog

The source's public REST details can omit episode links when a WordPress login
is required. The client then reads a title-specific metadata snapshot directly
from the `source-catalog` branch of this repository and plays the original CDN
URL. The account server is not involved in either operation.

`Refresh source episode catalog` logs in through the official HTTPS source form
using repository Actions secrets `HENTAI_SOURCE_USERNAME` and
`HENTAI_SOURCE_PASSWORD`. Only episode numbers, quality labels, original HTTPS
media URLs and source modification dates are published. Cookies, credentials and
account HTML remain in worker memory. Never add credentials to client assets.

The job runs every six hours and supports manual refresh. It processes three
titles concurrently, skips unchanged titles, retries transient transport errors
with limits, and keeps previous complete files when a refresh fails. Monitor
failed runs if the source changes its login or page format. An optional forced
run also refreshes unchanged titles.

Run parser checks with:

```sh
python -m unittest discover -s tools -p test_source_catalog.py
```

Use `tools/hentai_playback_probe.dart` as a separate web target for playback QA.
It uses the production source adapter and player and contains no credentials.
The browser test checks playback, duration, seeking and pause/resume at all
sample qualities in Chrome and iPhone-sized WebKit. This does not substitute
for physical-device testing.

Windows WebKit's remote-media transport may reject the CDN even when the same
unchanged MP4 plays from loopback. `MBN_WEBKIT_RELAY=1` enables an explicitly
labelled **test-only** loopback relay in the QA target. This verifies production
player decoding and controls with real source bytes, not direct Safari network
access. The release entry point has no relay hook or test configuration.
