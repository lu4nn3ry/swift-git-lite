# Repairing `libexpat.1.dylib` on iOS Rootless

Guide and reference procedure for resolving missing `libexpat.1.dylib` errors in iOS 15+ rootless jailbreak environments (Dopamine, Procursus, TrollStore).

---

## 1. Symptom

When attempting to perform remote Git operations over HTTPS (such as `git clone https://...`, `git pull`, or `git push`), Git terminates with an error:

```
dyld[XXXX]: Library not loaded: '@rpath/libexpat.1.dylib'
  Referenced from: '/var/jb/usr/libexec/git-core/git-remote-http'
  Reason: tried: '/var/jb/usr/lib/libexpat.1.dylib' (no such file)
zsh: abort      git clone https://...
```

---

## 2. Root Cause Analysis

1. **dyld Shared Cache in iOS 15+**:
   Apple combines system libraries into a unified memory-mapped cache (`dyld_shared_cache`). The file path `/usr/lib/libexpat.1.dylib` is registered inside this cache, but **does not exist as an independent file** on the root filesystem.
2. **Symlink Failure**:
   Creating a standard symlink via `ln -s /usr/lib/libexpat.1.dylib /var/jb/usr/lib/` fails or results in a broken link (`ENOENT`) because the kernel cannot resolve filesystem symlinks pointing to paths that exist exclusively in the dyld shared cache.
3. **Procursus Git Expectation**:
   The `git` package in Procursus links `git-remote-http` against `@rpath/libexpat.1.dylib`. At runtime, dyld searches `/var/jb/usr/lib/libexpat.1.dylib` and fails.

---

## 3. Resolution: Native Re-Export Shim

Rather than extracting massive files or relying on broken symlinks, the cleanest solution is to compile a dynamic library that **re-exports** the OS shared cache entry `/usr/lib/libexpat.1.dylib` and place it in `/var/jb/usr/lib/libexpat.1.dylib`.

### Option A: Automated Script

Run the included repair script directly on your iOS device:

```sh
sudo sh scripts/fix_libexpat.sh
```

### Option B: Manual Commands

Execute the following on the iOS device as `root` (or with `sudo`). The temporary file is created with `mktemp` — never use a fixed path in `/tmp`, which is vulnerable to symlink pre-planting (CWE-59) and TOCTOU swaps (CWE-367) while running as root:

```sh
# 0. Create a private temporary file (secure alternative to a fixed /tmp path)
TMP_DYLIB="$(mktemp /tmp/libexpat.XXXXXXXX)"

# 1. Compile the arm64 re-export shim
/var/jb/usr/bin/clang \
  -isysroot /var/jb/usr/share/SDKs/iPhoneOS.sdk \
  -target arm64-apple-ios15.0 \
  -dynamiclib \
  -install_name @rpath/libexpat.1.dylib \
  -Wl,-reexport_library,/usr/lib/libexpat.1.dylib \
  -o "$TMP_DYLIB"

# 2. Pseudo-sign with ldid
/var/jb/usr/bin/ldid -S "$TMP_DYLIB"

# 3. Install into Procursus rootless lib directory
cp "$TMP_DYLIB" /var/jb/usr/lib/libexpat.1.dylib
chmod 755 /var/jb/usr/lib/libexpat.1.dylib
ln -sf libexpat.1.dylib /var/jb/usr/lib/libexpat.dylib
rm -f "$TMP_DYLIB"
```

---

## 4. Verification

Verify that `git-remote-http` is able to link and run without dyld crashes:

```sh
VERIFY_DIR="$(mktemp -d)"
git clone https://github.com/lu4nn3ry/swift-git-lite.git "$VERIFY_DIR/verify-git"
rm -rf "$VERIFY_DIR"
```

If the clone succeeds without dyld library warnings, Git HTTPS operations are fully functional.

---

## 5. Alternatives

If compiling on-device is not feasible (e.g. `clang` or iOS SDK is not installed), use **GitLite** (`Sources/GitLite.swift`) for standalone, dependency-free local snapshot management.
