#!/usr/bin/env bash
# Prints an xcodebuild -destination for the newest available iPhone simulator,
# so CI doesn't hard-code a device name that changes between Xcode releases.
set -euo pipefail

xcrun simctl list devices available --json | python3 -c '
import json, re, sys

devices = json.load(sys.stdin)["devices"]
candidates = []
for runtime, entries in devices.items():
    match = re.search(r"SimRuntime\.iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    for device in entries:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            candidates.append((version, device["name"], device["udid"]))

if not candidates:
    sys.exit("No available iPhone simulator found")

version, name, udid = max(candidates)
print(f"Using {name} (iOS {version[0]}.{version[1]})", file=sys.stderr)
print(f"platform=iOS Simulator,id={udid}")
'
