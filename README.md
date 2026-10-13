# Swift GitLite

Tiny offline Git-like snapshot tool written in Swift for iOS/rootless environments where Git cannot start because `libexpat.1.dylib` is unavailable.

This is an educational local tool, not a wire-compatible Git implementation. It stores a JSON index and snapshots in `.gitlite/`. Use GitHub's API or `gh api` to publish files; no credential is stored here.

## Build

```sh
swiftc -sdk /var/jb/usr/share/SDKs/iPhoneOS.sdk -target arm64-apple-ios15.0 Sources/GitLite.swift -o gitlite
ldid -S gitlite
```

## Use

```sh
./gitlite init /path/project
./gitlite add /path/project
./gitlite status /path/project
./gitlite commit /path/project -m "first snapshot"
./gitlite log /path/project
```

License: MIT
