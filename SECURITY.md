# Security policy

This plugin changes how `sudo` authenticates, so security reports are taken
seriously.

## Reporting a vulnerability

Please report it privately. Do not open a public issue or pull request.

1. Go to the repository's **Security** tab on
   [GitHub](https://github.com/Babbletrax/omarchy-passwordless-sudo/security).
2. Choose **Report a vulnerability**.
3. Describe the problem, how to reproduce it, and what an attacker could do.

You should get a reply within a week. Please give time for a fix before
disclosing details publicly.

## In scope

- The helper acting for an account other than the one that authenticated.
- Enabling passwordless sudo without authentication.
- Installing a sudoers rule that `visudo` would reject, or one broader than
  the documented single line.
- Overwriting or deleting sudoers files the helper did not write.
- The widget reporting the wrong state (for example, showing off while
  passwordless sudo is on).

## Out of scope

Passwordless sudo itself is the feature. While the switch is on, anything
running as your user, including AI agents, can act as root. This is
documented in the README's usage warning and is not a vulnerability.
