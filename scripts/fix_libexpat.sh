#!/bin/sh
# fix_libexpat.sh - Fix missing libexpat.1.dylib on iOS Rootless (Dopamine / Procursus)
#
# Root cause:
# In iOS 15+ rootless environments, system libraries like libexpat reside in the
# dyld_shared_cache at /usr/lib/libexpat.1.dylib and do not exist as loose files
# on disk. Git packages (git-remote-http) expect @rpath/libexpat.1.dylib at
# /var/jb/usr/lib/libexpat.1.dylib. A plain symlink fails with ENOENT.
#
# Solution:
# Build and sign a native arm64 shim dylib with clang using
# -Wl,-reexport_library,/usr/lib/libexpat.1.dylib to re-export the cached library.

set -e

JB_PREFIX="${JB_PREFIX:-/var/jb}"
LIB_DIR="$JB_PREFIX/usr/lib"
TARGET_DYLIB="$LIB_DIR/libexpat.1.dylib"
TARGET_SYMLINK="$LIB_DIR/libexpat.dylib"

echo "=== iOS Rootless libexpat.1.dylib Repair Tool ==="

# 1. Quick check if native git-remote-http already works
if [ -f "$TARGET_DYLIB" ]; then
    if [ -x "$JB_PREFIX/usr/libexec/git-core/git-remote-http" ]; then
        if ! "$JB_PREFIX/usr/libexec/git-core/git-remote-http" 2>&1 | grep -q "libexpat"; then
            echo "[+] libexpat.1.dylib is already installed at $TARGET_DYLIB and functioning."
            exit 0
        fi
    fi
fi

# 2. Check root / sudo permissions
if [ "$(id -u)" -ne 0 ]; then
    echo "[!] Please run as root (or use sudo): sudo $0"
    exit 1
fi

# 3. Locate clang and SDK
CLANG="${JB_PREFIX}/usr/bin/clang"
if [ ! -x "$CLANG" ]; then
    CLANG="$(command -v clang || true)"
fi

if [ -z "$CLANG" ] || [ ! -x "$CLANG" ]; then
    echo "[-] Error: clang compiler not found in $JB_PREFIX/usr/bin/clang or PATH."
    echo "    Please install clang via your package manager (e.g. 'apt install clang' in Sileo/Zebra)."
    exit 1
fi

# Search for iPhoneOS SDK
SDK=""
for candidate in \
    "${JB_PREFIX}/usr/share/SDKs/iPhoneOS.sdk" \
    "${JB_PREFIX}/Developer/SDKs/iPhoneOS.sdk" \
    "/var/jb/usr/share/SDKs/iPhoneOS.sdk" \
    "/usr/share/SDKs/iPhoneOS.sdk"; do
    if [ -d "$candidate" ]; then
        SDK="$candidate"
        break
    fi
done

SDK_FLAG=""
if [ -n "$SDK" ]; then
    SDK_FLAG="-isysroot $SDK"
    echo "[*] Using SDK: $SDK"
else
    echo "[*] No explicit iPhoneOS.sdk found, trying native sysroot..."
fi

# Locate ldid
LDID="${JB_PREFIX}/usr/bin/ldid"
if [ ! -x "$LDID" ]; then
    LDID="$(command -v ldid || true)"
fi

# 4. Create a private temporary directory for the build artifact.
#    A fixed path in the world-writable /tmp would let a local attacker
#    pre-plant a symlink (CWE-59) or swap the file between compile and
#    install (CWE-367/TOCTOU) while this script runs as root.
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fix_libexpat.XXXXXXXX")" || {
    echo "[-] Error: could not create a secure temporary directory."
    exit 1
}
chmod 700 "$TMP_DIR"
TMP_DYLIB="$TMP_DIR/libexpat.1.dylib"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

echo "[*] Compiling re-export shim dylib for arm64..."
"$CLANG" $SDK_FLAG -target arm64-apple-ios15.0 -dynamiclib \
    -install_name @rpath/libexpat.1.dylib \
    -Wl,-reexport_library,/usr/lib/libexpat.1.dylib \
    -o "$TMP_DYLIB"

if [ -x "$LDID" ]; then
    echo "[*] Signing shim with ldid..."
    "$LDID" -S "$TMP_DYLIB"
else
    echo "[!] Warning: ldid not found, skipping signature (install ldid if execution fails)."
fi

# 5. Safety checks before installing: the artifact must be a regular file
#    (not a symlink) owned by the effective user (root).
if [ ! -f "$TMP_DYLIB" ] || [ -L "$TMP_DYLIB" ] || [ ! -O "$TMP_DYLIB" ]; then
    echo "[-] Error: temporary dylib failed safety checks (regular, root-owned file expected)."
    exit 1
fi

echo "[*] Installing to $LIB_DIR..."
mkdir -p "$LIB_DIR"
cp -f "$TMP_DYLIB" "$TARGET_DYLIB"
chmod 755 "$TARGET_DYLIB"
ln -sf libexpat.1.dylib "$TARGET_SYMLINK"

echo "[+] libexpat.1.dylib installed successfully!"
echo "[*] Verifying Git HTTPS remote capability..."
if [ -x "$JB_PREFIX/usr/libexec/git-core/git-remote-http" ]; then
    if "$JB_PREFIX/usr/libexec/git-core/git-remote-http" 2>&1 | grep -q "libexpat"; then
        echo "[-] Verification failed: git-remote-http still reports missing libexpat."
        exit 1
    else
        echo "[+] SUCCESS: git-remote-http loads libexpat correctly!"
    fi
else
    echo "[+] Done. Target installed at $TARGET_DYLIB."
fi
