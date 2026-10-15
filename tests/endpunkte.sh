#!/bin/sh
# Test the two audio paths the app uses, independent of the app.
W=/opt/wunderw/bin/wget
TODAY=$(date +%Y%m%d)
P3=/opt/wunderw/bin/python3

echo "=== OOM / kills in dmesg:"
dmesg 2>/dev/null | grep -i -E "oom|out of memory|killed process" | tail -8
echo "(empty = none)"
echo
echo "=== top RSS consumers:"
ps -eo rss,comm 2>/dev/null | sort -rn | head -8
echo
echo "=== A) pick a loopStreamId from today's schedule"
$W -q -O /home/user/sched.json --timeout=20 "https://audioapi.orf.at/oe1/api/json/5.0/broadcasts/$TODAY"
echo "sched.json bytes: $(wc -c < /home/user/sched.json)"
$P3 - <<'PY'
import json,sys
d=json.load(open('/home/user/sched.json'))
# find first broadcast id of the day
def walk(o):
    out=[]
    if isinstance(o,list):
        for x in o: out+=walk(x)
    elif isinstance(o,dict):
        if 'id' in o and ('title' in o or 'programKey' in o): out.append(o)
        for v in o.values(): out+=walk(v)
    return out
bs=walk(d)
print("broadcast-like entries:", len(bs))
for b in bs[:6]:
    print("  id=%s title=%r" % (b.get('id'), (b.get('title') or '')[:40]))
open('/home/user/firstid.txt','w').write(str(bs[0].get('id')) if bs else '')
PY
echo
ID=$(cat /home/user/firstid.txt 2>/dev/null)
echo "=== B) broadcast detail for id=$ID -> loopStreamId"
$W -q -O /home/user/bc.json --timeout=20 "https://audioapi.orf.at/oe1/api/json/5.0/broadcast/$ID"
$P3 - <<'PY'
import json
d=json.load(open('/home/user/bc.json'))
p=d.get('payload',d)
st=p.get('streams',[])
print("streams:", len(st))
for s in st[:3]: print("   ", s)
open('/home/user/loopid.txt','w').write(st[0].get('loopStreamId','') if st else '')
PY
echo
LID=$(cat /home/user/loopid.txt 2>/dev/null)
echo "=== C) the exact loopstream URL the app builds (loopid=$LID)"
$W --spider -S --timeout=15 --max-redirect=5 "https://loopstream01.apa.at/?channel=oe1&shoutcast=0&id=$LID" 2>&1 | sed -n '1,30p'
echo
echo "=== D) does gstreamer play the plain-http LIVE stream directly (no proxy)?"
gst-launch-0.10 playbin2 uri=http://ors-sn10.ors-shoutcast.at/oe1-q1a > /home/user/gst.log 2>&1 &
G=$!
sleep 10
kill $G 2>/dev/null; sleep 1; kill -9 $G 2>/dev/null
tail -12 /home/user/gst.log
