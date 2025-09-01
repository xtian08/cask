#!/bin/bash
# Upgrade Apache Log4j Core JARs with dry-run option
# Compatible with macOS/Linux

LATEST_VERSION="2.23.1"
LATEST_URL="https://repo1.maven.org/maven2/org/apache/logging/log4j/log4j-core/${LATEST_VERSION}/log4j-core-${LATEST_VERSION}.jar"
DOWNLOAD_DIR="/tmp/log4j-upgrade"
EXCLUDE_DIRS="^/Applications|^/Library/Java/JavaVirtualMachines"

DRY_RUN=true
[[ "$1" == "--dry-run" ]] && DRY_RUN=true

mkdir -p "$DOWNLOAD_DIR"

# --- Functions ---

# Find log4j-core jars
find_log4j_jars() {
    locate log4j-core-*.jar 2>/dev/null | grep -Ev "$EXCLUDE_DIRS"
}

# Extract version from JAR manifest
get_jar_version() {
    local jar="$1"
    unzip -p "$jar" META-INF/MANIFEST.MF 2>/dev/null | \
        grep "Implementation-Version" | \
        awk -F': ' '{print $2}' | tr -d '\r'
}

# Download latest jar if not already present
download_latest() {
    local target="$DOWNLOAD_DIR/log4j-core-${LATEST_VERSION}.jar"
    if [[ ! -f "$target" ]]; then
        echo "[+] Downloading log4j-core ${LATEST_VERSION}..."
        curl -sSL -o "$target" "$LATEST_URL"
    fi
    echo "$target"
}

# Replace old jar with latest
replace_jar() {
    local old_jar="$1"
    local latest_jar="$2"
    local dir
    dir="$(dirname "$old_jar")"
    if $DRY_RUN; then
        echo "[DRY-RUN] Would replace $old_jar → $dir/log4j-core-${LATEST_VERSION}.jar"
    else
        echo "[+] Replacing $old_jar → $dir/log4j-core-${LATEST_VERSION}.jar"
        sudo cp "$latest_jar" "$dir/"
        sudo rm -f "$old_jar"
    fi
}

# --- Main ---
echo "[*] Searching for log4j-core JARs..."
jars=$(find_log4j_jars)

if [[ -z "$jars" ]]; then
    echo "[!] No log4j-core JARs found."
    exit 0
fi

if ! $DRY_RUN; then
    latest_jar="$(download_latest)"
else
    latest_jar="$DOWNLOAD_DIR/log4j-core-${LATEST_VERSION}.jar"
fi

for jar in $jars; do
    version=$(get_jar_version "$jar")
    if [[ -z "$version" ]]; then
        echo "[?] Could not detect version for $jar"
        continue
    fi

    echo "[*] Found $jar (version $version)"

    # Compare versions (basic string comparison)
    if [[ "$version" < "$LATEST_VERSION" ]]; then
        echo "[!] Vulnerable version detected ($version)"
        replace_jar "$jar" "$latest_jar"
    else
        echo "[+] Already up-to-date ($version)"
    fi
done

echo "[*] Upgrade process complete. (Dry-run = $DRY_RUN)"
