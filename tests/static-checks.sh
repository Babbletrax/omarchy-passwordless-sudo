#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2015  # literal patterns and ok/bad one-liners are intentional
# Read-only checks: the plugin's files agree with each other and the helper
# keeps its security invariants. Safe to run anywhere.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
ok()  { printf 'ok   - %s\n' "$1"; }
bad() { printf 'FAIL - %s\n' "$1"; fail=1; }
has()   { local name="$1" pattern="$2" file="$3"; if grep -qE -- "$pattern" "$file"; then ok "$name"; else bad "$name"; fi; }
lacks() { local name="$1" pattern="$2" file="$3"; if grep -qE -- "$pattern" "$file"; then bad "$name"; else ok "$name"; fi; }

id="$(jq -r .id manifest.json)"
helper=toggle-passwordless-sudo

# Consistency between manifest, widget and helper.
[[ -n "$id" && "$id" != null ]] && ok "manifest has an id" || bad "manifest id missing"
has   "widget moduleName matches manifest id" "moduleName: \"$id\"" BarWidget.qml
has   "widget finds the helper next to itself" 'Qt\.resolvedUrl\("toggle-passwordless-sudo"\)' BarWidget.qml
lacks "widget has no hardcoded install path"  '\.config/omarchy/plugins|/home/' BarWidget.qml
[[ -x "$helper" ]] && ok "helper is executable" || bad "helper is not executable"
bash -n "$helper" && ok "helper parses" || bad "helper does not parse"

# Security invariants (see README).
has   "strict mode"                        '^set -euo pipefail$'                                 "$helper"
has   "target user comes from pkexec/sudo" 'PKEXEC_UID:-\$\{SUDO_UID:-'                         "$helper"
has   "status uses the calling user"       'name="\$\(id -un\)"'                                 "$helper"
has   "refuses root as the target"         'refusing to manage passwordless sudo for root'       "$helper"
has   "user names are validated"           "USERNAME_RE='\^\[a-z_\]"                              "$helper"
has   "exactly one argument accepted"      '^\(\( \$# == 1 \)\)'                                 "$helper"
lacks "no hardcoded target user"           'TARGET_USER=|readonly [A-Z_]*USER="'                 "$helper"
has   "rule file is the managed drop-in"   "/etc/sudoers.d/90-passwordless-sudo-%s"              "$helper"
has   "enable authenticates with pkexec"   'exec pkexec "\$0" --enable'                          "$helper"
has   "disable uses non-interactive sudo"  'exec sudo -n -- "\$0" --disable'                     "$helper"
has   "new rule is checked with visudo"    'visudo -cf "\$temporary"'                            "$helper"
has   "rule file mode is 0440"             'chmod 0440 "\$temporary"'                            "$helper"
has   "refuses to overwrite"               'refusing to overwrite'                               "$helper"
has   "refuses unrecognised contents"      'refusing to remove unrecognized contents'            "$helper"
lacks "no eval"                            '(^|[^[:alnum:]_])eval([[:space:]]|$)'                 "$helper"
lacks "no remote downloads"                '(curl|wget)[[:space:]]'                              "$helper"
lacks "no world-writable modes"            'chmod [0-7]*[2367][[:space:]]|chmod (a|o)\+w'        "$helper"

# visudo must run before the rule is moved into place.
v=$(grep -n 'visudo -cf' "$helper" | cut -d: -f1)
m=$(grep -n 'mv "$temporary" "$rule_path"' "$helper" | cut -d: -f1)
[[ -n "$v" && -n "$m" && "$v" -lt "$m" ]] && ok "visudo runs before install" || bad "visudo must run before mv"

exit "$fail"
