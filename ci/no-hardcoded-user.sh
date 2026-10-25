#!/usr/bin/env bash
# Fail if any committed file hardcodes a user's home directory, or if the
# helper names a fixed account. The plugin must work for whoever installs it,
# so it may never contain a specific user name or home path.
#
# Usage: ci/no-hardcoded-user.sh [rev...]   (default HEAD; checks every commit
# reachable from the given revisions, so history is covered too)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

revs=("$@")
(( ${#revs[@]} )) || revs=(HEAD)
mapfile -t commits < <(git rev-list "${revs[@]}")

fail=0
report() {
  local what="$1" hits="$2"
  [[ -n "$hits" ]] || return 0
  echo "no-hardcoded-user: $what (commit:file:line):" >&2
  printf '%s\n' "$hits" | sed -E 's/^([0-9a-f]{7})[0-9a-f]+:/\1:/' | sort -t: -k2,3 -u >&2
  fail=1
}

# A literal home directory such as /home/<name> or /Users/<name>.
report "hardcoded home directory" \
  "$(git grep -n -I -E '(/home|/Users)/[A-Za-z0-9_][A-Za-z0-9_.-]*' "${commits[@]}" -- . 2>/dev/null || true)"

# A fixed account name assigned in the helper.
report "fixed user name in the helper" \
  "$(git grep -n -I -E '(TARGET_USER|USER_NAME|USERNAME)=["'"'"']?[a-z_]' "${commits[@]}" -- toggle-passwordless-sudo 2>/dev/null || true)"

if (( fail )); then
  echo "no-hardcoded-user: FAILED. Derive the user at runtime instead of naming one." >&2
  exit 1
fi
echo "no-hardcoded-user: ${#commits[@]} commit(s) clean"
