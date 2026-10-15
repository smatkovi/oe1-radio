#!/bin/sh
# Packt die App in ein Harmattan-.deb.
#
#   tools/build-deb.sh            # Fassung aus src/oe1radio
#   tools/build-deb.sh 1.5.43     # Fassung von Hand
#
# Gebaut wird nichts -- die App ist ein Python-Skript. Das .deb ist
# architekturfrei ("all"), laeuft also auf N9 und N950 gleichermassen.
set -e
cd "$(dirname "$0")/.."

# Fassung aus dem Kopf des Skripts lesen, damit sie nur an einer Stelle steht.
VERSION=${1:-$(sed -n 's/^Version \([0-9.]*\) .*/\1/p' src/oe1radio | head -1)}
[ -n "$VERSION" ] || { echo "Fassung nicht erkannt -- als Argument angeben"; exit 1; }

STAGE=build/stage
DEB=build/oe1-radio_${VERSION}_all.deb

rm -rf "$STAGE"
mkdir -p "$STAGE/DEBIAN" \
         "$STAGE/opt/oe1-radio/qml" \
         "$STAGE/usr/share/applications" \
         "$STAGE/usr/share/icons/hicolor/80x80/apps"

cp src/oe1radio          "$STAGE/opt/oe1-radio/oe1radio"
cp src/podcast_proxy.py  "$STAGE/opt/oe1-radio/podcast_proxy.py"
cp qml/main.qml          "$STAGE/opt/oe1-radio/qml/main.qml"
cp data/oe1-radio.desktop "$STAGE/usr/share/applications/oe1-radio.desktop"
cp icons/oe1-radio-80.png "$STAGE/usr/share/icons/hicolor/80x80/apps/oe1-radio.png"
chmod 755 "$STAGE/opt/oe1-radio/oe1radio" "$STAGE/opt/oe1-radio/podcast_proxy.py"

# Replaces auf die eigene aeltere Fassung: so beschwert sich dpkg beim
# Hochstufen nicht ueber die schon vorhandenen Dateien.
cat > "$STAGE/DEBIAN/control" <<CONTROL
Package: oe1-radio
Version: $VERSION
Section: multimedia
Priority: optional
Architecture: all
Maintainer: smatkovi
Replaces: oe1-radio (<< $VERSION)
Depends: python, python-pyside.qtcore, python-pyside.qtgui, python-pyside.qtdeclarative, libqtm-multimedia
Description: Ö1 Radio für MeeGo Harmattan
 Livestream, 7 Tage OnDemand, Podcasts, Suche, Sleep Timer.
 v$VERSION: Ausgabe auf UTF-8 festgenagelt -- die Startansicht gibt
 der App kein LANG mit, wodurch jedes print mit Umlaut die App beendete.
XB-Maemo-Display-Name: Ö1 Radio
XB-Maemo-Icon-26: /usr/share/icons/hicolor/80x80/apps/oe1-radio.png
CONTROL

# chmod gehoert hierher und nicht ins postinst: unter aegis scheitert ein
# chmod im postinst (siehe harmattan-deb-ustar), die Rechte stehen schon im tar.
cat > "$STAGE/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
exit 0
POSTINST
chmod 755 "$STAGE/DEBIAN/postinst"

python3 tools/mkdeb.py "$STAGE" "$DEB"
echo "fertig: $DEB"
