---
name: omarchy-passwordless-sudo
description: Install, maintain, or test the Omarchy bar widget that toggles a scoped passwordless sudo rule (plugin id passwordless-sudo-toggle). Use for requests about this widget or its sudoers toggle; do not activate it for unrelated sudo work.
---

# Omarchy passwordless sudo widget

A native Omarchy Shell plugin (`passwordless-sudo-toggle`). Source:
https://github.com/Babbletrax/omarchy-passwordless-sudo

The live install at `~/.config/omarchy/plugins/passwordless-sudo-toggle/` is a
git checkout of the repo. Make changes there and commit them. Don't keep a
second copy of the plugin files anywhere else.

## Layout

| Path | Purpose |
|---|---|
| `manifest.json` | Plugin manifest (bar widget, right section) |
| `BarWidget.qml` | Lock icon; left-click toggles, right-click refreshes, polls every 10 s |
| `toggle-passwordless-sudo` | Helper: `--status`, `--toggle`, `--enable`, `--disable` |
| `ci/omarchy-plugin-validate` | Vendored copy of Omarchy's validator, used in CI |
| `ci/no-hardcoded-user.sh` | Fails on literal home paths or fixed account names |
| `ci/leak-check.sh` | Fails if tracked files match private patterns (CI and pre-push) |
| `tests/static-checks.sh` | Read-only consistency and security-invariant checks |
| `tests/integration.sh` | Real sudo tests; only run inside a container |
| `skills/` | This skill (the public, generic version) |

`--status` reads the public, content-free marker
`/var/lib/passwordless-sudo-<user>.enabled` (root:root 0444) instead of the
root-only sudoers file. This stops the bar's polling from flooding the journal
with failed `sudo -n` checks. `--enable` writes the marker and `--disable`
removes it together with the rule.

## Invariants

- Do not edit packaged files under `/usr/share/omarchy/`.
- The target account is never hardcoded or passed as an argument. Status uses
  the calling user. Changes use `PKEXEC_UID`/`SUDO_UID`, refuse root, and accept
  only plain account names. The rule lives only at
  `/etc/sudoers.d/90-passwordless-sudo-<user>`, mode 0440 root:root.
- Never commit a user name or home path. CI's `no-hardcoded-user` job enforces
  this across the whole history.
- Enabling must require Polkit authentication (`pkexec`). Disabling may use the
  active passwordless rule (`sudo -n`).
- Validate new rule content with `visudo -cf` before moving it into place.
- Refuse to overwrite or delete a rule file whose contents are not exactly the
  expected single line.
- Never toggle passwordless sudo as a side effect of installation, maintenance,
  or testing. Change its state only when the user explicitly requests that.
- `tests/static-checks.sh` enforces several of these. If you change the helper
  on purpose, update the matching check in the same commit.
- This repo is public. Never commit hostnames, IPs, internal URLs or account
  names from a private environment. Keep those in a separate private skill.

## Install or update

- Fresh install:
  `omarchy plugin add https://github.com/Babbletrax/omarchy-passwordless-sudo.git --enable`
- Update: `git -C ~/.config/omarchy/plugins/passwordless-sudo-toggle pull`
  (or `omarchy plugin update`).
- Run `omarchy-plugin-validate ~/.config/omarchy/plugins/passwordless-sudo-toggle`
  afterwards. Keep the widget in the right bar section, normally immediately
  before `omarchy.power`.

## Test

1. `bash tests/static-checks.sh`: read-only, safe anywhere.
2. Integration tests modify sudoers and refuse to run outside a container:
   ```sh
   docker run --rm -e PASSWORDLESS_SUDO_TEST_SANDBOX=1 -v "$PWD":/w:ro -w /w archlinux:base \
     bash -c 'pacman -Sy --noconfirm --needed sudo util-linux shadow >/dev/null && bash tests/integration.sh'
   ```
   Never run `tests/integration.sh` on the host.
3. Read-only host checks (do not change the toggle state):
   - Run the installed helper with `--status`.
   - When it reports enabled, confirm `sudo -n /usr/bin/id -u` returns `0`
     without prompting.
   - Run `sudo -n /usr/sbin/visudo -cf /etc/sudoers` and require a successful
     parse of the managed fragment and the full configuration.

Some agent sandboxes set `no_new_privs`, making sudo fail inside the sandbox
even when the host rule works. In that case, repeat the read-only checks
outside the sandbox rather than treating the failure as a widget failure.
