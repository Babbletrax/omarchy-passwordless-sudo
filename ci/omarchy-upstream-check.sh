#!/usr/bin/env bash
# Check the plugin against the latest Omarchy, so a breaking Omarchy change
# shows up in CI before it shows up in the bar.
#
#   1. The vendored ci/omarchy-plugin-validate still matches upstream.
#   2. Upstream's validator accepts the plugin.
#   3. The bar widget API this plugin uses still exists.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

upstream_url="${OMARCHY_UPSTREAM_URL:-https://github.com/omacom/omarchy.git}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git clone --quiet --depth 1 --filter=blob:none --sparse "$upstream_url" "$work/omarchy"
git -C "$work/omarchy" sparse-checkout set --no-cone /bin/omarchy-plugin-validate /shell/Ui/
echo "upstream-check: Omarchy $(git -C "$work/omarchy" rev-parse --short HEAD) ($(git -C "$work/omarchy" branch --show-current))"

fail=0
ok()  { printf 'ok   - %s\n' "$1"; }
bad() { printf 'FAIL - %s\n' "$1"; fail=1; }

# 1. Vendored validator: our copy is upstream with two header lines added after
#    the shebang, so compare everything after those.
if diff -u <(tail -n +2 "$work/omarchy/bin/omarchy-plugin-validate") <(tail -n +4 ci/omarchy-plugin-validate) > "$work/validator.diff"; then
  ok "vendored validator matches upstream"
else
  bad "vendored validator differs from upstream (re-sync ci/omarchy-plugin-validate)"
  cat "$work/validator.diff"
fi

# 2. Upstream validator accepts the plugin.
if bash "$work/omarchy/bin/omarchy-plugin-validate" .; then
  ok "upstream validator accepts the plugin"
else
  bad "upstream validator rejects the plugin"
fi

# 3. Bar widget API used by BarWidget.qml.
ui="$work/omarchy/shell/Ui"
api_has() {
  local name="$1" pattern="$2"; shift 2
  if grep -qE -- "$pattern" "$@" 2>/dev/null; then ok "$name"; else bad "$name"; fi
}
api_has "BarWidget has moduleName"            'property string moduleName'      "$ui/BarWidget.qml"
api_has "BarWidget has bar"                   'property [A-Za-z]+ bar\b'        "$ui/BarWidget.qml"
api_has "BarIconButton still exists"          'WidgetButton|BarIconButton'      "$ui/BarIconButton.qml"
api_has "button has text"                     'property string text\b'          "$ui/BarIconButton.qml" "$ui/WidgetButton.qml"
api_has "button has active"                   'property bool active\b'          "$ui/BarIconButton.qml" "$ui/WidgetButton.qml"
api_has "button has interactive"              'property bool interactive\b'     "$ui/BarIconButton.qml" "$ui/WidgetButton.qml"
api_has "button has tooltipText"              'property string tooltipText\b'   "$ui/BarIconButton.qml" "$ui/WidgetButton.qml"
api_has "button has pressed(button) signal"   'signal pressed\(int [a-zA-Z]+\)' "$ui/BarIconButton.qml" "$ui/WidgetButton.qml"
api_has "active state uses the urgent colour" 'activeColor: .*urgent'           "$ui/BarIconButton.qml" "$ui/WidgetButton.qml"

exit "$fail"
