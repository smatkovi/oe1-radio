# -*- coding: utf-8 -*-
"""Treibt die Abspielwege ohne Oberflaeche: 7-Tage und Livestream."""
import imp, sys, os, subprocess, time

from PySide.QtCore import QTimer
from PySide.QtGui import QApplication

app = QApplication(sys.argv)
m = imp.load_source('oe1mod', '/home/user/oe1radio_test')
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
    bid = int(open('/home/user/firstid.txt').read().strip())
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
