#!/bin/sh
# Veroeffentlicht das Paket einer Fassung als Release dieses Repositoriums.
#
#   tools/release.sh 1.5.43 [build/oe1-radio_1.5.43_all.deb]
#
# gh ist auf dem Arch-Rechner angemeldet, nicht hier -- die Datei geht also
# erst dorthin. /tmp hat dort eine Benutzerquote, deshalb /dev/shm.
set -e
cd "$(dirname "$0")/.."

VERSION=$1
[ -n "$VERSION" ] || { echo "usage: tools/release.sh <version> [deb]" >&2; exit 2; }
DEB=${2:-build/oe1-radio_${VERSION}_all.deb}
[ -f "$DEB" ] || { echo "kein Paket: $DEB" >&2; exit 2; }

if [ -n "$BUILD_HOST" ]; then
    HOST=$BUILD_HOST
elif ssh -o BatchMode=yes -o ConnectTimeout=4 sebastian@192.168.1.21 true 2>/dev/null; then
    HOST=sebastian@192.168.1.21
else
    HOST=arch
fi
REPO=${REPO:-smatkovi/oe1-radio}
TAG=v$VERSION
WORK=/dev/shm/oe1-release

NOTES=$(mktemp)
cat > "$NOTES" <<NOTE
Ö1 Radio $VERSION für MeeGo Harmattan (Nokia N9 und N950).

Das Paket ist architekturfrei, dasselbe \`.deb\` passt auf beide Geräte.

    sudo dpkg -r oe1-radio            # nur nötig, wenn noch die OpenRepos-Fassung liegt
    sudo aegis-dpkg -i oe1-radio_${VERSION}_all.deb

\`aegis-dpkg\`, nicht \`dpkg\` -- sonst lässt aegis nichts daraus starten.
NOTE

ssh -oConnectTimeout=20 "$HOST" "mkdir -p $WORK"
scp -oConnectTimeout=20 "$DEB" "$NOTES" "$HOST:$WORK/" >/dev/null
BASE=$(basename "$DEB")
NBASE=$(basename "$NOTES")

# Pruefsumme vergleichen -- scp legt bei erschoepfter Quote stumm
# abgeschnittene Dateien an.
HERE=$(md5sum "$DEB" | cut -d' ' -f1)
THERE=$(ssh -oConnectTimeout=20 "$HOST" "md5sum $WORK/$BASE | cut -d' ' -f1")
[ "$HERE" = "$THERE" ] || { echo "Pruefsumme passt nicht: $HERE != $THERE" >&2; exit 1; }

ssh -oConnectTimeout=60 "$HOST" \
    "cd $WORK && gh release create $TAG $BASE --repo $REPO --title 'Ö1 Radio $VERSION' --notes-file $NBASE"
ssh -oConnectTimeout=20 "$HOST" "rm -rf $WORK"
rm -f "$NOTES"
echo "fertig: $TAG"
