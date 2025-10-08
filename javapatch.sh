#!/bin/bash
set -e

# Variables
ZIP_URL="https://cdn.azul.com/zulu/bin/zulu8.88.0.19-ca-jre8.0.462-macosx_aarch64.zip"
TMP_DIR="/tmp/jre_update_$$"
DEST_DIR="/Applications/XNAT-Desktop-Client.app/Contents/Resources/jre"

# Require root privileges
if [[ $EUID -ne 0 ]]; then
    echo "Please run this script as root (use: sudo $0)"
    exit 1
fi

echo "[*] Creating temporary working directory..."
mkdir -p "$TMP_DIR"

echo "[*] Downloading new JRE from Azul..."
curl -L "$ZIP_URL" -o "$TMP_DIR/jre.zip"

echo "[*] Extracting JRE package..."
unzip -q "$TMP_DIR/jre.zip" -d "$TMP_DIR"

# Locate 'Home' folder dynamically (Azul sometimes nests inside zulu-8.jre/Contents/Home)
HOME_DIR=$(find "$TMP_DIR" -type d -path "*/Contents/Home" | head -n 1)

if [ -z "$HOME_DIR" ]; then
    echo "[!] ERROR: Could not find the 'Contents/Home' directory in extracted archive."
    find "$TMP_DIR" -type d | sed 's/^/[DEBUG] Found: /'
    exit 1
fi

echo "[*] Removing old embedded JRE (no backup kept to avoid XDR detection)..."
rm -rf "$DEST_DIR"

echo "[*] Installing new JRE from:"
echo "    $HOME_DIR"
cp -R "$HOME_DIR" "$DEST_DIR"

echo "[*] Setting ownership and permissions..."
chown -R root:wheel "$DEST_DIR"
chmod -R 755 "$DEST_DIR"

echo "[✓] JRE successfully updated in:"
echo "    $DEST_DIR"

# Verify version
if [ -x "$DEST_DIR/bin/java" ]; then
    echo "[*] Verifying installed JRE version:"
    "$DEST_DIR/bin/java" -version
else
    echo "[!] Warning: java binary not found under $DEST_DIR/bin/"
fi

# Cleanup
rm -rf "$TMP_DIR"
echo "[*] Temporary files cleaned up."
