# Ö1 Radio for MeeGo Harmattan

The Austrian public radio station **Ö1** on the Nokia N9 and N950: the live
stream, the seven-day catch-up archive ("7 Tage"), the podcasts, a search over
the programme, and a sleep timer.

MeeGo Harmattan, PySide / Qt 4.7 with a `com.nokia.meego` QML interface.
Architecture-independent `.deb`, so the same package serves the N9 and the
N950.

![icon](icons/oe1-radio-80.png)

## Why this needs more than an `Audio` element

Two platform facts shape the whole app.

**Harmattan's gstreamer cannot do TLS.** `souphttpsrc` was built without SSL
and answers every `https://` URI with `SSL support not available` — which
rules out the QML `Audio` element, `QMediaPlayer` and `playbin2` alike. ORF's
catch-up archive is HTTPS-only, and unlike some broadcasters it does not serve
the same bytes over plain `http://`.

**Qt 4.7's own OpenSSL is from 2011** and never gets past a TLS 1.2
handshake, so the app cannot fetch the programme data through Qt either.

So the app splits the two jobs:

| job | how |
| --- | --- |
| programme data, JSON | `/opt/wunderw/bin/wget` as a subprocess — that wget links the newer OpenSSL |
| catch-up and live audio | the same wget downloads to a cache file, and a small HTTP server on the loopback hands it to gstreamer as plain `http://` |

The loopback proxy is what makes the archive playable at all: gstreamer only
ever sees `http://127.0.0.1:<port>/stream.mp3`. It passes `Range` headers
through, so seeking inside a broadcast works, and it serves from the cache
file while the download is still running, so playback starts after the first
~128 KB rather than after 15 MB.

The live stream is plain HTTP at the source and would not strictly need the
proxy, but it goes through the same path so that the sleep timer, seeking and
the buffering indicator behave identically in both modes.

## The 1.5.43 fix: the launcher gives an app no `LANG`

Versions up to 1.5.42 died **one second after the icon was tapped**, which
looked from the outside as though neither the live stream nor the seven-day
archive worked any more.

The cause was one line. Harmattan's launcher starts applications with an empty
environment — no `LANG`, no `LC_ALL` — and their stdout is a pipe, not a
terminal. Python 2.6 then reports `sys.stdout.encoding` as `None` and falls
back to ASCII, so the very first statement in `main()`

```python
print u"=== Ö1 Radio 1.5.42 Starting ==="
```

raised `UnicodeEncodeError` on the `Ö` before the `QApplication` was even
built. Started from a terminal — where `LANG` is set — the app ran fine, which
is exactly why the bug survived a release.

It would not have stopped at startup either. Of the 107 `print` statements,
87 interpolate data, and show titles look like `Ö1 Frühjournal`. Inside the
worker threads that resolve a stream URL, that same exception kills the thread
silently, before `playUrl` is ever set — a UI that looks alive and plays
nothing.

The fix wraps stdout and stderr once, at import time, so all 107 prints and
`traceback.print_exc()` are covered:

```python
if getattr(sys.stdout, 'encoding', None) is None:
    sys.stdout = _Utf8Stream(sys.stdout)
```

`_Utf8Stream` encodes `unicode` as UTF-8 and passes `str` through untouched —
a `codecs.getwriter` would have choked on the byte strings that
`traceback.print_exc()` writes.

**The lesson generalises:** on Harmattan, never test a GUI app only from a
terminal. `env -i DISPLAY=:0 /opt/<app>/<app> > log 2>&1` reproduces what the
launcher actually does.

## Layout

| path | what |
| --- | --- |
| `src/oe1radio` | the application: backend, proxies, ORF API client |
| `src/podcast_proxy.py` | standalone loopback proxy for podcast episodes |
| `qml/main.qml` | the whole interface |
| `data/oe1-radio.desktop` | launcher entry — note `Icon=` needs the full path |
| `tools/build-deb.sh` | builds the `.deb`; takes the version from the script header |
| `tools/mkdeb.py` | ar + tar packer, because Harmattan's dpkg predates xz |
| `tools/n9ssh.sh` | ssh to the device (its OpenSSH needs `ssh-rsa`) |
| `tests/endpunkte.sh` | probes every ORF endpoint from the device |
| `tests/abspielprobe.py` | drives both playback paths without the UI |

## Building and installing

```sh
tools/build-deb.sh                 # -> build/oe1-radio_1.5.43_all.deb
scp ... oe1-radio_1.5.43_all.deb user@<device>:/home/user/
sudo aegis-dpkg -i /home/user/oe1-radio_1.5.43_all.deb
```

`aegis-dpkg`, not `dpkg` — a package installed with plain `dpkg` is refused at
launch. And if an older build is still installed **from OpenRepos**, aegis
will not let a self-built package replace it:

```
Aegis rejecting ...: package 'oe1-radio' already installed from
'com.nokia.maemo/net.openrepos.harmattan' -- not replacing it from
less trusted source
```

Remove it first (`sudo dpkg -r oe1-radio`), then install. The cache in
`~/MyDocs/.oe1cache` is untouched by that.

## Testing without the interface

`tests/abspielprobe.py` loads the backend, calls the real slots and pulls
bytes through the proxy, which separates "the proxy serves audio" from
"gstreamer plays it":

```sh
sh tests/endpunkte.sh                      # legt u.a. die Sendungsnummer ab
python tests/abspielprobe.py ondemand      # 7 Tage
python tests/abspielprobe.py live          # Livestream
```

Both run **on the device** (Python 2.6 with PySide). `abspielprobe.py` takes
the broadcast id as a third argument and otherwise reads the one
`endpunkte.sh` left in `/home/user/firstid.txt`; a second argument overrides
which script to load, so an unreleased build can be probed before it is
packaged.

On the N950 it reports ~2.5 MB in ten seconds for a catch-up broadcast and
~420 KB for the live stream.

## What it costs on the device

Measured on the N950 (OMAP3630, 1 GB RAM, `CLK_TCK` 100):

| | |
| --- | --- |
| start until QML is loaded | **8 s**, 5.0 s of CPU |
| playing, steady state | **2 % of one core** (41 ticks in 15 s) |
| resident memory | **73 MB**, 2 threads |
| an empty PySide process with a `QDeclarativeView` | 30 MB |
| `sr`, a sibling PySide app in the same class | 63 MB |

So the runtime floor is about 30 MB; the rest is this app's QML interface, the
parsed programme data and the proxy. Nothing is expensive while it plays — the
cost is the eight seconds before the interface appears.

**Would Rust be faster?** Not where it hurts. Steady state is already 2 %, so
there is nothing to win there, and the 5 s of startup CPU is shared between
things Rust would replace (importing Python and PySide, turning 129 KB and
361 KB of JSON into dicts) and things it would not (compiling the 67 KB
`main.qml`, which Qt does either way). There is also no Rust binding for
Qt 4.7 / QtQuick 1.1, so a rewrite means the shape the sibling projects
already use: a Rust helper for fetching and the loopback proxy behind a Qt 4
shell. The better argument for doing it is not speed but that a `rustls`
helper would drop the dependency on `/opt/wunderw/bin/wget`, which only exists
on a device that has had the newer OpenSSL installed — a stock N9 has not.

## License

GPL-3.0-or-later, see [LICENSE](LICENSE).
