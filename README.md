# Passwordless sudo bar widget

An on/off switch in the Omarchy top bar for passwordless sudo. Turn it on and
`sudo` stops asking for your password. Turn it off and the password prompt
comes back.

**Read the [usage warning](#usage-warning) before turning it on.** While it is on,
your user and any AI agents you run can do anything as root without asking you.

## How it works

| State | Icon in the top bar | What sudo does |
|---|---|---|
| **Off** (default) | Closed padlock in the normal bar colour (grey or white, depending on your theme) | Asks for your password as usual |
| **On** | Open padlock in your theme's warning colour (red in most themes) | Runs without asking for a password |
| Changing | Spinner | Wait for it to finish |

- **Left-click** the icon to switch between on and off.
  - Turning it **on** asks for your password once, through the normal desktop
    authentication prompt.
  - Turning it **off** happens straight away, with no prompt.
- **Right-click** re-checks the current state. The widget also re-checks it
  every 10 seconds.
- A desktop notification confirms each change.
- **It stays on until you turn it off.** There is no timeout, and the setting
  survives logging out and rebooting. The icon shows the current state after
  every restart.

## Usage warning

**Use this at your own risk.** Turning the switch on removes the password check
that normally stands between your user account and full control of the system.

While it is on:

- **Anything running as your user can act as root without asking you.** That
  includes you, your scripts, every app you run, and anything that has
  compromised your account.
- **AI agents can run root commands without your permission.** Coding
  assistants and agents (Claude Code, Codex, Hermes and similar tools) run as
  your user. With passwordless sudo on, they can run `sudo` commands with no
  password prompt and nothing for you to approve.
- **An agent's actions can be dangerous.** An agent can misunderstand a task,
  follow instructions hidden in a web page, file or repo it reads, or simply
  make a mistake. With root access, it could:
  - delete or overwrite system files or your data
  - change system settings, firewall rules or user accounts
  - install or remove packages
  - break the system so it no longer boots
- **Nothing undoes these actions.** Root commands take effect immediately, and
  this plugin keeps no record of what ran while the switch was on.

Good practice:

- Leave it **off** by default. Turn it on only for a specific task, and turn it
  off as soon as that task is done.
- Don't leave it on while an AI agent runs unattended, or while it runs with
  permission checks turned off.
- Keep the red open padlock in view so you always know when it is on.
- Remember that it **stays on across reboots** until you turn it off.

This software is provided "as is", without warranty of any kind (see
[LICENSE](LICENSE)). You are responsible for what runs on your system while
passwordless sudo is enabled.

## Safety details

- It only ever affects **your own account**. The helper never takes a user
  name as input: it uses the account that authenticated through the desktop
  prompt (`pkexec`) or `sudo`. It refuses to act for `root`, and it only
  accepts plain account names.
- The helper only ever touches `/etc/sudoers.d/90-passwordless-sudo-<your user>`.
  It checks the new rule with `visudo` before installing it.
- It refuses to overwrite or delete that file if its contents are not exactly
  the rule it wrote.
- The widget checks the state through a content-free marker file
  (`/var/lib/passwordless-sudo-<your user>.enabled`), so polling never needs sudo.

## Install

```sh
omarchy plugin add https://github.com/Babbletrax/omarchy-passwordless-sudo.git --enable
```

It installs to `~/.config/omarchy/plugins/passwordless-sudo-toggle/`.

## Remove

Turn the switch **off** first, so the sudo rule is removed, then:

```sh
omarchy plugin remove passwordless-sudo-toggle
```

If the plugin was removed while it was still on, delete the rule by hand:

```sh
sudo rm "/etc/sudoers.d/90-passwordless-sudo-$USER" "/var/lib/passwordless-sudo-$USER.enabled"
```

## Contributing

Issues and pull requests are welcome on GitHub. See [CONTRIBUTING.md](CONTRIBUTING.md)
for how changes are tested and land, and [SECURITY.md](SECURITY.md) to report a
vulnerability privately.

## Agent skill

`skills/omarchy-passwordless-sudo/SKILL.md` is a generic agent skill for installing,
maintaining and testing this plugin. Copy it into your agent's skills directory to use it.

## Tests and CI

| Stage | Job | What it checks |
|---|---|---|
| lint | `shellcheck` | shellcheck on every script |
| sync | `github-sync` | Hourly (GitLab only): if a pull request was merged on GitHub, opens a GitLab merge request with those exact commits, which merges itself once the pipeline passes |
| lint | `no-hardcoded-user` | Fails if any file, in any commit, hardcodes a home directory (`/home/<name>`) or gives the helper a fixed account name |
| lint | `leak-check` | `ci/leak-check.sh` fails if any committed file or commit message matches the owner's private patterns. The patterns live in a masked CI variable (and a local file for the pre-push hook), never in the repo |
| validate | `plugin-validate` | `bash -n` syntax check, Omarchy's plugin validator (vendored in `ci/`) and `tests/static-checks.sh`: manifest/widget/helper agree, and the helper keeps its security rules (target user from `pkexec`/`sudo` only, never root, `visudo` before install, `pkexec` to enable, 0440 mode, no `eval` or downloads) |
| validate | `omarchy-upstream-check` | Weekly, and when the widget or validator changes: checks the plugin against the latest Omarchy (validator still matches upstream, upstream accepts the plugin, and the bar widget API it uses still exists) |
| test | `sudo-integration` | `tests/integration.sh` enables, toggles and disables the rule against real `sudo` in a throwaway Arch container, including refusal of tampered or pre-existing files |
| security | `secret_detection` + `secret-detection-gate` | GitLab secret detection over the full history; the gate fails the pipeline on any finding |

A weekly pipeline schedule re-runs everything.

The table above is the private GitLab pipeline, where changes land. On GitHub,
every pull request runs the same regression suite in GitHub Actions
(`.github/workflows/ci.yml`), plus a leak check that only runs trusted code
from `main` (`.github/workflows/leak-check.yml`).

`tests/static-checks.sh` is read-only and safe to run locally.
`tests/integration.sh` writes to `/etc/sudoers.d` and refuses to run outside a
container. To run it locally:

```sh
docker run --rm -e PASSWORDLESS_SUDO_TEST_SANDBOX=1 -v "$PWD":/w:ro -w /w archlinux:base \
  bash -c 'pacman -Sy --noconfirm --needed sudo util-linux shadow >/dev/null && bash tests/integration.sh'
```
