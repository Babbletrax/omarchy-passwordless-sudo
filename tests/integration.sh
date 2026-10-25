#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2015  # literal patterns and ok/bad one-liners are intentional
# End-to-end tests for toggle-passwordless-sudo.
#
# These tests really write to /etc/sudoers.d, so they refuse to run anywhere
# except a throwaway CI container. Never run them on a real machine.
set -euo pipefail

if [[ "${PASSWORDLESS_SUDO_TEST_SANDBOX:-}" != 1 || ! -f /.dockerenv && ! -f /run/.containerenv ]]; then
  echo "refusing to run: these tests modify sudoers and only run inside a CI container" >&2
  exit 2
fi
(( EUID == 0 )) || { echo "must run as root inside the container" >&2; exit 2; }

repo="$(cd "$(dirname "$0")/.." && pwd)"
helper=/usr/local/bin/toggle-passwordless-sudo
user=tester
other=bystander
rule_file="/etc/sudoers.d/90-passwordless-sudo-$user"
state_file="/var/lib/passwordless-sudo-$user.enabled"
rule="$user ALL=(ALL:ALL) NOPASSWD: ALL"
log=/tmp/passwordless-sudo-logger.log

pass=0
fail=0
ok()   { printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf 'FAIL - %s\n' "$1"; fail=$((fail + 1)); }
check() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
refute() { local name="$1"; shift; if "$@"; then bad "$name"; else ok "$name"; fi; }
as_user() { runuser -u "$user" -- "$@"; }
# Simulate pkexec: root, with PKEXEC_UID naming the user who authenticated.
as_pkexec() { local uid="$1"; shift; env -u SUDO_UID PKEXEC_UID="$uid" "$@"; }

# --- sandbox setup ---------------------------------------------------------
id "$user"  >/dev/null 2>&1 || useradd -m "$user"
id "$other" >/dev/null 2>&1 || useradd -m "$other"
id dot.user >/dev/null 2>&1 || useradd -m dot.user
uid="$(id -u "$user")"
install -m 0755 "$repo/toggle-passwordless-sudo" "$helper"
# Containers have no /dev/log; record logger calls instead of failing on them.
for dir in /usr/local/sbin /usr/local/bin; do
  printf '#!/bin/sh\necho "$*" >> %s\n' "$log" > "$dir/logger"
  chmod 0755 "$dir/logger"
done
: > "$log"; chmod 0666 "$log"
rm -f /etc/sudoers.d/90-passwordless-sudo-* /var/lib/passwordless-sudo-*.enabled

# --- argument handling -----------------------------------------------------
refute "no arguments is a usage error" "$helper"
refute "unknown argument is a usage error" "$helper" --bogus
refute "extra arguments are rejected (cannot name a user)" as_pkexec "$uid" "$helper" --enable "$other"
check  "nothing written for a named user" test ! -e "/etc/sudoers.d/90-passwordless-sudo-$other"

# --- initial state ---------------------------------------------------------
refute "status reports disabled at start" as_user "$helper" --status
refute "user cannot sudo without a password at start" as_user sudo -n true

# --- who can change it -----------------------------------------------------
refute "--enable refuses without root" as_user "$helper" --enable
check  "no rule written by unprivileged --enable" test ! -e "$rule_file"
refute "--disable refuses without root" as_user "$helper" --disable
refute "--enable refuses when the requesting user is unknown" env -u PKEXEC_UID -u SUDO_UID "$helper" --enable
refute "--enable refuses root as the target" as_pkexec 0 "$helper" --enable
check  "no rule written for root" test ! -e /etc/sudoers.d/90-passwordless-sudo-root
refute "--enable refuses a uid with no account" as_pkexec 59999 "$helper" --enable
refute "--enable refuses a user name containing a dot" as_pkexec "$(id -u dot.user)" "$helper" --enable
check  "no rule written for the dotted name" bash -c '! compgen -G "/etc/sudoers.d/90-passwordless-sudo-dot*" >/dev/null'

# --- enable (as pkexec would run it) ---------------------------------------
check "--enable succeeds for the authenticated user" as_pkexec "$uid" "$helper" --enable
check "rule file exists" test -f "$rule_file"
check "rule file has exactly the expected line" \
  bash -c '[[ "$(cat "$1")" == "$2" && $(wc -l < "$1") -eq 1 ]]' _ "$rule_file" "$rule"
check "rule file is root:root 0440" \
  bash -c '[[ "$(stat -c "%U:%G %a" "$1")" == "root:root 440" ]]' _ "$rule_file"
check "state marker is root:root 0444" \
  bash -c '[[ "$(stat -c "%U:%G %a" "$1")" == "root:root 444" ]]' _ "$state_file"
check "full sudoers config still parses" visudo -c
check "no temporary files left in sudoers.d" \
  bash -c '! compgen -G "/etc/sudoers.d/.passwordless-sudo-toggle.*" >/dev/null'
check "enable was logged" grep -q "enabled passwordless sudo for $user" "$log"
check "status reports enabled for the user" as_user "$helper" --status
refute "status stays disabled for another user" runuser -u "$other" -- "$helper" --status
check "user can now sudo without a password" as_user sudo -n true
refute "other users are unaffected" runuser -u "$other" -- sudo -n true

# --- refuse to overwrite ---------------------------------------------------
before="$(sha256sum "$rule_file")"
refute "second --enable refuses to overwrite" as_pkexec "$uid" "$helper" --enable
check  "rule file unchanged after refused enable" \
  bash -c '[[ "$(sha256sum "$1")" == "$2" ]]' _ "$rule_file" "$before"

# --- disable via the bar's --toggle path (sudo -n while rule is active) ----
check "--toggle disables via passwordless sudo" as_user "$helper" --toggle
check "rule file removed" test ! -e "$rule_file"
check "state marker removed" test ! -e "$state_file"
check "disable was logged" grep -q "disabled passwordless sudo for $user" "$log"
refute "status reports disabled after toggle" as_user "$helper" --status
refute "user needs a password again" as_user sudo -n true
check "--disable is a no-op when already disabled" as_pkexec "$uid" "$helper" --disable

# --- tampered rule file is left alone --------------------------------------
printf '%s\n%s\n' "$rule" 'Defaults !authenticate' > "$rule_file"
chmod 0440 "$rule_file"
refute "--disable refuses unrecognised contents" as_pkexec "$uid" "$helper" --disable
check  "tampered file left in place" test -f "$rule_file"
printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$user" > "$rule_file"
refute "--disable refuses a different single-line rule" as_pkexec "$uid" "$helper" --disable
check  "different rule left in place" test -f "$rule_file"
refute "--enable refuses when an unexpected file exists" as_pkexec "$uid" "$helper" --enable
check  "unexpected file not overwritten" grep -qx "$user ALL=(ALL) NOPASSWD: ALL" "$rule_file"
rm -f "$rule_file" "$state_file"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
