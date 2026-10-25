# Contributing

Contributions are welcome. Open an issue or a pull request on
[GitHub](https://github.com/Babbletrax/omarchy-passwordless-sudo).

## How changes land

- Pull requests are reviewed and merged on GitHub as usual.
- Every pull request runs the regression suite in GitHub Actions:
  - shellcheck and bash syntax
  - Omarchy's plugin validator
  - the consistency and security-invariant checks
  - a check that nothing hardcodes a user name or home path
  - the full sudo integration tests in a throwaway Arch container
- A leak check also scans each pull request for details of the maintainer's
  private environment. It only ever runs the trusted copy of the check from
  `main`, and never executes code from your pull request.
- The maintainer also keeps a private copy of the repo, which re-runs the same
  checks on every change. Merged commits keep their IDs and authorship.

## Ground rules

- **Never weaken the safety rules** without discussing it in an issue first:
  - the helper only acts for the account that authenticated
  - it refuses root and takes no user name as input
  - every rule is checked with `visudo` before it is installed
  - it refuses to touch files it didn't write
  - enabling needs authentication

  `tests/static-checks.sh` enforces these. If you change one on purpose,
  update the matching check in the same pull request and explain why.
- **No user names or home paths** in code, docs or commit messages. Work out
  the user at runtime.
- **Add a test** for every behaviour change or bug fix. `tests/integration.sh`
  runs against real `sudo` inside a container, so add a case there.
- Keep pull requests focused, one change per pull request.

## Run the checks locally

```sh
shellcheck --severity=style --shell=bash toggle-passwordless-sudo tests/*.sh ci/*.sh
bash ci/omarchy-plugin-validate .
bash tests/static-checks.sh
bash ci/no-hardcoded-user.sh HEAD
```

The integration tests modify sudoers, so they refuse to run outside a
container:

```sh
docker run --rm -e PASSWORDLESS_SUDO_TEST_SANDBOX=1 -v "$PWD":/w:ro -w /w archlinux:base \
  bash -c 'pacman -Sy --noconfirm --needed sudo util-linux shadow >/dev/null && bash tests/integration.sh'
```

**Never run `tests/integration.sh` on your own machine.**

## Security issues

Don't open a public issue for a vulnerability. See [SECURITY.md](SECURITY.md).
