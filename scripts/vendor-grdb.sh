#!/usr/bin/env bash
# Re-vendors GRDB.swift at a pinned tag into Vendor/GRDB.
#
# GRDB only supports SQLCipher through SwiftPM by forking it and editing its
# Package.swift (see "GRDB+SQLCipher" comments upstream). We keep that fork
# in-tree: upstream sources are copied verbatim, and Vendor/GRDB/Package.swift
# is our hand-maintained, SQLCipher-only manifest. This script never touches
# that manifest — review it against upstream's when bumping the tag.
#
# Usage: scripts/vendor-grdb.sh [tag]   (default: the tag in Vendor/GRDB/VENDORED.md)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$root/Vendor/GRDB"
tag="${1:-$(sed -n 's/^- Tag: `\(.*\)`$/\1/p' "$dest/VENDORED.md")}"
[ -n "$tag" ] || { echo "No tag given and none found in VENDORED.md" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$tag" \
  https://github.com/groue/GRDB.swift "$work/grdb"
commit="$(git -C "$work/grdb" rev-parse HEAD)"

rm -rf "$dest/GRDB" "$dest/Sources" "$dest/LICENSE"
cp -R "$work/grdb/GRDB" "$dest/GRDB"
rm -rf "$dest/GRDB/Documentation.docc"
mkdir -p "$dest/Sources"
cp -R "$work/grdb/Sources/GRDBSQLCipher" "$dest/Sources/GRDBSQLCipher"
cp "$work/grdb/LICENSE" "$dest/LICENSE"

sed -i.bak \
  -e "s/^- Tag: \`.*\`$/- Tag: \`$tag\`/" \
  -e "s/^- Commit: \`.*\`$/- Commit: \`$commit\`/" \
  "$dest/VENDORED.md"
rm -f "$dest/VENDORED.md.bak"

echo "Vendored GRDB $tag ($commit)."
echo "Review upstream's Package.swift for this tag against Vendor/GRDB/Package.swift:"
echo "  https://github.com/groue/GRDB.swift/blob/$tag/Package.swift"
