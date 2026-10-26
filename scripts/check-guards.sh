#!/usr/bin/env bash
# Enforces Vivra's privacy and determinism rules (docs/PLAN.md §2, §10).
# Runs in CI on Linux; needs only bash and grep.
set -uo pipefail

cd "$(dirname "$0")/.."

# First-party Swift sources. Vendor/ is third-party and excluded.
roots=(App AppTests Packages)
failed=0

fail() {
  echo "::error::$1"
  failed=1
}

# grep_swift <regex> [path...] — prints matches in first-party Swift files,
# ignoring // comments.
grep_swift() {
  local pattern="$1"
  shift
  grep -rnE --include='*.swift' --exclude-dir=.build "$pattern" "${@:-${roots[@]}}" 2>/dev/null \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//'
}

check() {
  local description="$1" pattern="$2"
  shift 2
  local hits
  hits="$(grep_swift "$pattern" "$@")"
  if [ -n "$hits" ]; then
    fail "$description"
    echo "$hits"
  fi
}

# 1. No network code. Vivra makes no network calls of its own.
check "Networking APIs are not allowed" \
  '\bURLSession\b|\bURLRequest\b|\bNWConnection\b|\bNWPathMonitor\b|^[[:space:]]*import[[:space:]]+Network\b|\bWKWebView\b|\bCFNetwork\b'

# 2. No unstructured logging. Use VivraLogging.Log.
check "print/NSLog/dump are not allowed; use Log" \
  '(^|[^.[:alnum:]_])(print|debugPrint|dump|NSLog|os_log)\('
logger_hits="$(grep_swift '\bLogger\(' | grep -v '^Packages/VivraCore/Sources/VivraLogging/')"
if [ -n "$logger_hits" ]; then
  fail "Create loggers only in VivraLogging"
  echo "$logger_hits"
fi

# 3. Determinism: core logic takes injected clocks, calendars and locales.
check "Use an injected clock/calendar/time zone/locale in VivraCore" \
  '\bDate\(\)|\bDate\.now\b|\bCalendar\.current\b|\bTimeZone\.current\b|\bLocale\.current\b' \
  Packages/VivraCore/Sources

# 4. Dependencies: local packages only, plus the approved list.
remote_deps="$(grep -nE '\.package\([[:space:]]*(url|name):' Packages/*/Package.swift)"
if [ -n "$remote_deps" ]; then
  fail "First-party packages may only depend on local packages (.package(path:))"
  echo "$remote_deps"
fi
vendor_remote="$(grep -nE '\.package\(' Vendor/*/Package.swift \
  | grep -vF 'https://github.com/sqlcipher/SQLCipher.swift.git')"
if [ -n "$vendor_remote" ]; then
  fail "Vendored packages may only depend on approved remote packages"
  echo "$vendor_remote"
fi
if grep -nE '^[[:space:]]+(url|github):' project.yml; then
  fail "project.yml may only reference local packages"
fi

if [ "$failed" -ne 0 ]; then
  echo "Guard checks failed."
  exit 1
fi
echo "Guard checks passed."
