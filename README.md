# Swift GitLite

Tiny offline Git-like snapshot tool written in Swift for iOS and rootless environments (Dopamine, Procursus, TrollStore).

Designed for situations where Git is unavailable or broken (e.g. `libexpat.1.dylib` runtime missing errors), or when you need zero-dependency local snapshots and change tracking.

---

## 🛠️ Fixing Native Git on iOS Rootless (`libexpat.1.dylib`)

If you want native Git HTTPS operations (`git clone`, `git pull`, `git push`) to work on iOS 15+ rootless environments, the issue occurs because `libexpat.1.dylib` resides inside Apple's `dyld_shared_cache` rather than as a standalone disk file in `/usr/lib/`. A standard symlink fails (`ENOENT`).

### Automatic Repair

Run the automated repair script on your iOS device:

```sh
sudo sh scripts/fix_libexpat.sh
```

### Manual Repair

Compile a native arm64 shim dylib that re-exports the system shared cache. The temporary file is created with `mktemp` — never use a fixed path in `/tmp`, which is vulnerable to symlink pre-planting and TOCTOU swaps while running as root:

```sh
TMP_DYLIB="$(mktemp /tmp/libexpat.XXXXXXXX)"

/var/jb/usr/bin/clang \
  -isysroot /var/jb/usr/share/SDKs/iPhoneOS.sdk \
  -target arm64-apple-ios15.0 \
  -dynamiclib \
  -install_name @rpath/libexpat.1.dylib \
  -Wl,-reexport_library,/usr/lib/libexpat.1.dylib \
  -o "$TMP_DYLIB"

/var/jb/usr/bin/ldid -S "$TMP_DYLIB"
sudo cp "$TMP_DYLIB" /var/jb/usr/lib/libexpat.1.dylib
sudo chmod 755 /var/jb/usr/lib/libexpat.1.dylib
sudo ln -sf libexpat.1.dylib /var/jb/usr/lib/libexpat.dylib
rm -f "$TMP_DYLIB"
```

For full details and troubleshooting, see the [Fix libexpat Guide](skills/fix-libexpat-ios.md).

---

## 📦 Swift GitLite (Standalone Tool)

GitLite is an educational, zero-dependency local snapshot tool. It stores a JSON index and file snapshots in `.gitlite/`. Use GitHub's API or `gh api` to publish files; no credentials are required or stored.

### Build GitLite

```sh
swiftc -sdk /var/jb/usr/share/SDKs/iPhoneOS.sdk -target arm64-apple-ios15.0 Sources/GitLite.swift -o gitlite
ldid -S gitlite
```

### Usage

```sh
# Initialize tracking
./gitlite init /path/project

# Stage files
./gitlite add /path/project

# View changes (modified, untracked, deleted)
./gitlite status /path/project

# Create a snapshot commit
./gitlite commit /path/project -m "first snapshot"

# View commit history
./gitlite log /path/project
```

See [skills/gitlite-workflow.md](skills/gitlite-workflow.md) for detailed workflow guidance.

---

## License

MIT
