# Changelog

All notable changes to this plugin are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-10-27

### Added

- Bar widget (`passwordless-sudo-toggle`) that switches passwordless sudo on
  and off for your own account. A closed padlock in the normal bar colour
  means off; an open padlock in the theme's warning colour means on; a spinner
  shows a change in progress.
- Left click toggles. Turning it on asks for your password once through the
  desktop authentication prompt (`pkexec`); turning it off needs no prompt.
  Right click re-checks the state, which is also polled every 10 seconds, and
  a desktop notification confirms each change. The setting persists across
  logouts and reboots until you turn it off.
- `toggle-passwordless-sudo` helper with strict safety rules: it only acts for
  the account that authenticated (from `pkexec` or `sudo`, never from an
  argument), refuses `root` and unusual account names, checks the rule with
  `visudo` before installing it with mode 0440, and refuses to overwrite or
  delete a sudoers file whose contents it did not write.
- State is read from a content-free marker file, so polling never needs sudo.
- Usage warning in the README about AI agents and other software gaining root
  without a prompt while the switch is on.
- Generic agent skill (`skills/omarchy-passwordless-sudo/SKILL.md`) for
  installing, maintaining and testing the plugin.
- CI on GitHub Actions and GitLab: ShellCheck, bash syntax, Omarchy's plugin
  validator, consistency and security-invariant checks, a no-hardcoded-user
  check, a private-details leak check, secret detection, a weekly check
  against the latest Omarchy, and sudo integration tests in a throwaway Arch
  container.
- Contributing guide, security policy with private vulnerability reporting,
  and issue templates.

[1.0.0]: https://github.com/Babbletrax/omarchy-passwordless-sudo/releases/tag/v1.0.0
