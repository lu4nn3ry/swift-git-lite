# GitLite offline workflow

Use when native Git cannot start because a runtime library is unavailable.

## Initialize

Run: ./gitlite init /path/to/project

Creates .gitlite/index.json and .gitlite/commits/. The .gitlite directory is skipped during collection.

## Stage and inspect

Run: ./gitlite add /path/to/project
Then: ./gitlite status /path/to/project

add records paths, sizes, and modification timestamps. status reports modified, deleted, and untracked files.

## Snapshot

Run: ./gitlite commit /path/to/project -m snapshot-description
Then: ./gitlite log /path/to/project

Snapshots are local JSON records. GitLite is educational and is not wire-compatible with Git. Publish source files using an authenticated Git client or hosting API.

## Safety

- Never put access tokens, private keys, or personal data in a skill file.
- Review status before creating a snapshot.
- Keep .gitlite local unless its format is explicitly needed.
