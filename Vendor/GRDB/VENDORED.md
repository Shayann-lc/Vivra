# Vendored GRDB.swift (SQLCipher build)

- Upstream: https://github.com/groue/GRDB.swift
- Tag: `v7.11.1`
- Commit: `b83108d10f42680d78f23fe4d4d80fc88dab3212`
- License: MIT (see `LICENSE`)

## Why vendored

GRDB supports SQLCipher under SwiftPM only via a fork with an edited
`Package.swift` (upstream's README, "Encryption"). Rather than depend on a
third-party fork, the upstream sources are copied here unmodified and
`Package.swift` is ours.

## What differs from upstream

- `Package.swift` is rewritten following upstream's `GRDB+SQLCipher` comments:
  the `GRDBSQLite` system library is removed, the `GRDBSQLCipher` target and
  the `SQLCipher.swift` dependency (pinned exactly) are added, and
  `SQLITE_HAS_CODEC` / `SQLCipher` are defined. The test target is dropped.
- `GRDB/Documentation.docc`, tests, Xcode projects and CocoaPods files are not
  copied.

Nothing under `GRDB/` or `Sources/` is edited by hand.

## Updating

```sh
scripts/vendor-grdb.sh v7.x.y
```

Then compare upstream's `Package.swift` with ours and carry over any change to
targets, settings or minimum SQLCipher version.
