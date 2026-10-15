# -*- coding: utf-8 -*-
"""Treibt die Abspielwege ohne Oberflaeche: 7-Tage und Livestream."""
import imp, sys, os, subprocess, time

from PySide.QtCore import QTimer
from PySide.QtGui import QApplication

USAGE = """Aufruf (auf dem Geraet):

    python abspielprobe.py ondemand|live [skript] [sendungsnummer]

skript ist die zu pruefende Fassung, voreingestellt die installierte
/opt/oe1-radio/oe1radio -- so laesst sich ein Bau pruefen, bevor er paketiert
ist. Die Sendungsnummer braucht nur 'ondemand'; ohne sie wird die genommen,
die tests/endpunkte.sh in /home/user/firstid.txt abgelegt hat.
"""

if len(sys.argv) < 2 or sys.argv[1] not in ('ondemand', 'live'):
    sys.stderr.write(USAGE)
    sys.exit(2)

SKRIPT = sys.argv[2] if len(sys.argv) > 2 else '/opt/oe1-radio/oe1radio'
if not os.path.exists(SKRIPT):
    sys.stderr.write("kein Skript: %s\n" % SKRIPT)
    sys.exit(2)

app = QApplication(sys.argv)
m = imp.load_source('oe1mod', SKRIPT)
print "stdout wrapper in module: %s" % type(m.sys.stdout).__name__

helper = m.Oe1Helper()
state = {}

def onUrl():
    if 'url' in state:
        return
    state['url'] = helper.url
    print "*** playUrlChanged -> %r" % helper.url
    QTimer.singleShot(100, pull)

def onErr():
    state['err'] = getattr(helper, 'errorMsg', '?')
    print "*** errorOccurred"

helper.playUrlChanged.connect(onUrl)
try:
    helper.errorOccurred.connect(onErr)
except Exception as e:
    print "errorOccurred not connectable: %s" % e

def pull():
    """Zieht ein paar Sekunden Audio durch den Vermittler."""
    url = state['url']
    if not url.startswith('http'):
        print "url is not http, nothing to pull"
        app.quit(); return
    out = '/home/user/pull.bin'
    if os.path.exists(out):
        os.remove(out)
    p = subprocess.Popen(['/opt/wunderw/bin/wget', '-q', '-O', out, url])
    t0 = time.time()
    while time.time() - t0 < 10:
        time.sleep(0.5)
    p.terminate()
    time.sleep(0.5)
    try:
        p.kill()
    except Exception:
        pass
    size = os.path.getsize(out) if os.path.exists(out) else 0
    state['bytes'] = size
    print "*** pulled %d bytes in 10s from the proxy" % size
    app.quit()

MODE = sys.argv[1]
if MODE == 'ondemand':
    if len(sys.argv) > 3:
        bid = int(sys.argv[3])
    else:
        quelle = '/home/user/firstid.txt'
        if not os.path.exists(quelle):
            sys.stderr.write("%s fehlt -- erst tests/endpunkte.sh laufen "
                             "lassen oder die Nummer angeben\n" % quelle)
            sys.exit(2)
        bid = int(open(quelle).read().strip())
    print "calling getPlaybackUrl(%d)" % bid
    helper.getPlaybackUrl(bid)
else:
    live = m.STREAM_URLS['low']
    print "calling startLiveProxy(%s)" % live
    helper.startLiveProxy(live)

def timeout():
    if 'url' not in state:
        print "--- 40s up, still no url"
        app.quit()

QTimer.singleShot(40000, timeout)
app.exec_()

print "=== RESULT mode=%s url=%r bytes=%r err=%r" % (
    MODE, state.get('url'), state.get('bytes'), state.get('err'))
sys.exit(0 if state.get('bytes') else 1)
