#!/bin/sh
# Installe Knowledge World pour l'utilisateur courant (sans mot de passe) :
#   curl -fsSL https://github.com/goodview-soft/knowledge-world/releases/latest/download/install.sh | sh
# Désinstaller : sh install.sh --uninstall
set -e
APP="$HOME/.local/share/knowledgeworld"
BIN="$HOME/.local/bin/knowledgeworld"
DESK="$HOME/.local/share/applications/knowledgeworld.desktop"
URL="https://github.com/goodview-soft/knowledge-world/releases/latest/download/KnowledgeWorld-linux.zip"

if [ "$1" = "--uninstall" ]; then
	rm -rf "$APP" "$BIN" "$DESK"
	echo "Knowledge World désinstallé."
	exit 0
fi

mkdir -p "$APP" "$(dirname "$BIN")" "$(dirname "$DESK")"
HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
if [ -f "$HERE/KnowledgeWorld.x86_64" ]; then
	SRC="$HERE"                        # lancé depuis le zip décompressé
else
	command -v unzip >/dev/null || { echo "Installer d'abord unzip (sudo apt install unzip)."; exit 1; }
	TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
	echo "Téléchargement…"
	curl -fsSL -o "$TMP/sl.zip" "$URL"
	unzip -q "$TMP/sl.zip" -d "$TMP"
	SRC="$TMP/KnowledgeWorld"
fi
cp -f "$SRC"/KnowledgeWorld.x86_64 "$SRC"/knowledge-world.sh "$SRC"/icon.svg "$SRC"/install.sh "$APP"/
chmod +x "$APP/KnowledgeWorld.x86_64" "$APP/knowledge-world.sh"
ln -sf "$APP/knowledge-world.sh" "$BIN"
cat > "$DESK" <<D
[Desktop Entry]
Type=Application
Name=Knowledge World
Comment=Univers 3D de connaissances
Exec=$APP/knowledge-world.sh
Icon=$APP/icon.svg
Terminal=false
Categories=Education;Office;
D
command -v update-desktop-database >/dev/null && update-desktop-database "$(dirname "$DESK")" 2>/dev/null || true
echo "Knowledge World installé : menu des applications, ou commande « knowledgeworld »."
