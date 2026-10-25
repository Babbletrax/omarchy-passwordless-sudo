#!/usr/bin/env bash
# Classify the risk of a change and write a plain-language report.
#
# Usage: ci/risk-report.sh <base-rev> <head-rev>
# Prints "risk=<low|medium|high>" on the first line, then a Markdown report.
#
# Tiers decide how a change merged on GitHub enters the private build:
#   low     documentation only: merges automatically
#   medium  tests, CI and other code: one-tap approval
#   high    anything that runs as root or in the desktop shell, agent
#           instructions, and the safety checks themselves: typed approval
#
# This script is always run from the trusted main branch, never from the
# incoming change, so a change cannot lower its own risk.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

base="${1:?usage: risk-report.sh <base-rev> <head-rev>}"
head="${2:?usage: risk-report.sh <base-rev> <head-rev>}"

rank() { case "$1" in low) echo 1 ;; medium) echo 2 ;; high) echo 3 ;; esac; }

# classify <path> -> "tier|what it is|worst case"
classify() {
  case "$1" in
    toggle-passwordless-sudo)
      echo "high|The helper script. It runs as root through pkexec and sudo.|Any code here runs as root on every machine that updates." ;;
    BarWidget.qml)
      echo "high|The bar widget. It runs inside your desktop shell and decides which commands the bar launches.|Runs any command as your user, or shows the wrong on/off state." ;;
    manifest.json)
      echo "high|The plugin manifest. It tells Omarchy which files to load.|Makes Omarchy load a different file as the widget." ;;
    skills/*)
      echo "high|Instructions that AI agents read and follow.|Tells your agents to run commands, which run as root while passwordless sudo is on." ;;
    tests/static-checks.sh|ci/leak-check.sh|ci/no-hardcoded-user.sh|ci/risk-report.sh|ci/github-sync.sh|ci/omarchy-plugin-validate|.gitlab-ci.yml|.github/workflows/leak-check.yml)
      echo "high|A safety check or part of the approval flow.|Switches off a check so a dangerous change passes unnoticed, or runs code on your homelab CI runner, which can reach your home network." ;;
    tests/*|ci/*|.github/workflows/*)
      echo "medium|Test or CI code. It runs on CI runners, including your homelab runner.|Weakens the regression tests, or probes your home network from CI." ;;
    LICENSE)
      echo "medium|The licence.|Changes the legal terms of the project." ;;
    .github/ISSUE_TEMPLATE/*|*.md)
      echo "low|Documentation or issue templates.|Misleading text. No code runs." ;;
    *)
      echo "medium|A file this policy doesn't recognise.|Unknown, so it needs a look." ;;
  esac
}

tier=low
checks_changed=no
rows=""
while IFS=$'\t' read -r meta path rest; do
  # --raw lines: ":<oldmode> <newmode> <oldsha> <newsha> <status>\t<path>[\t<newpath>]"
  read -r old_mode new_mode _ _ status <<<"${meta#:}"
  [[ -n "${rest:-}" ]] && path="$rest"   # renames and copies: use the new path
  IFS='|' read -r t what worst <<<"$(classify "$path")"
  # A file that becomes executable is code, whatever its name says.
  if [[ "$new_mode" == 100755 && "$old_mode" != 100755 ]]; then
    t=high; worst="$worst It is newly executable."
  fi
  case "$path" in
    tests/static-checks.sh|ci/leak-check.sh|ci/no-hardcoded-user.sh|ci/risk-report.sh|ci/github-sync.sh|.gitlab-ci.yml|.github/workflows/*) checks_changed=yes ;;
  esac
  (( $(rank "$t") > $(rank "$tier") )) && tier="$t"
  case "${status:0:1}" in A) s=added ;; D) s=deleted ;; R) s=renamed ;; *) s=changed ;; esac
  rows+="| \`$path\` | $s | **$t** | $what | $worst |"$'\n'
done < <(git diff --raw --no-abbrev -M "$base" "$head")

# shellcheck disable=SC2016  # the backticks are Markdown, not command substitution
commits="$(git log --format='- `%h` %s (%an)' "$base..$head")"

echo "risk=$tier"
cat <<EOF
## Risk: ${tier^^}

| File | Change | Risk | What it is | Worst case if malicious |
|---|---|---|---|---|
${rows}
**Safety checks or CI modified:** ${checks_changed}

**Commits:**

${commits}

**Size:** $(git diff --shortstat "$base" "$head")
EOF
