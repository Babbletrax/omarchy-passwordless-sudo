#!/usr/bin/env bash
# Fail if any committed file, commit message, author or committer matches a
# private pattern.
#
# This repo is mirrored publicly, so details of the owner's private environment
# (hostnames, IPs, account names) must never be committed. The patterns are
# kept outside the repo, so this file reveals nothing:
#   - CI: masked variable LEAK_PATTERNS_B64 (base64 of the pattern list)
#   - locally: $LEAK_PATTERNS_FILE, default ~/.config/leak-check/patterns
# The list holds one case-insensitive extended regex per line; blank lines and
# lines starting with # are ignored.
#
# Usage: ci/leak-check.sh [rev...]   (default HEAD; scans every commit reachable
# from the given revisions, so history is checked as well as the latest tree)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

patterns_file="${LEAK_PATTERNS_FILE:-$HOME/.config/leak-check/patterns}"
raw="$(mktemp)"
patterns="$(mktemp)"
trap 'rm -f "$raw" "$patterns"' EXIT

if [[ -n "${LEAK_PATTERNS_B64:-}" ]]; then
  printf '%s' "$LEAK_PATTERNS_B64" | base64 -d > "$raw"
elif [[ -r "$patterns_file" ]]; then
  cat "$patterns_file" > "$raw"
else
  echo "leak-check: no patterns found (set LEAK_PATTERNS_B64 or create $patterns_file)" >&2
  exit 2
fi
grep -vE '^[[:space:]]*(#|$)' "$raw" > "$patterns" || true
[[ -s "$patterns" ]] || { echo "leak-check: pattern list is empty" >&2; exit 2; }

revs=("$@")
(( ${#revs[@]} )) || revs=(HEAD)
mapfile -t commits < <(git rev-list "${revs[@]}")

found=0
file_hits="$(git grep -n -I -i -E -f "$patterns" "${commits[@]}" -- . 2>/dev/null || true)"
if [[ -n "$file_hits" ]]; then
  echo "leak-check: private patterns found in committed files (commit:file:line):" >&2
  # Show short commit ids and collapse the same hit repeated across commits.
  printf '%s\n' "$file_hits" | sed -E 's/^([0-9a-f]{7})[0-9a-f]+:/\1:/' | sort -t: -k2,3 -u >&2
  found=1
fi

for c in "${commits[@]}"; do
  if git log -1 --format=%B "$c" | grep -qiE -f "$patterns"; then
    echo "leak-check: private pattern in commit message of ${c:0:7}" >&2
    found=1
  fi
  # Author and committer names and emails are public too once mirrored.
  if git log -1 --format='%an%n%ae%n%cn%n%ce' "$c" | grep -qiE -f "$patterns"; then
    echo "leak-check: private pattern in author or committer of ${c:0:7}" >&2
    found=1
  fi
done

if (( found )); then
  echo "leak-check: FAILED. Remove the private details (rewrite history if they were committed)." >&2
  exit 1
fi
echo "leak-check: ${#commits[@]} commit(s) clean against $(wc -l < "$patterns") pattern(s)"
