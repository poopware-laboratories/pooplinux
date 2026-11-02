# Security Policy

Poop Linux is a from-scratch distribution. Its kernel, C library, init, package manager and signing infrastructure are all in scope. This policy explains what to report, how to report it, and what you can expect from us.

## Reporting a vulnerability

**Do not open a public issue, pull request or discussion for a security problem.**

Report privately through GitHub's private vulnerability reporting for `poopware-laboratories/pooplinux`:

1. Open the repository's **Security** tab.
2. Choose **Report a vulnerability**.
3. Describe the problem and include the details listed below.

If private vulnerability reporting is unavailable to you, contact a maintainer listed in [`MAINTAINERS.md`](MAINTAINERS.md) through a private channel. Do not post details publicly to ask for a channel.

### What to include

- The affected component and the version or commit SHA (for example a `pkgmgr` release, a kernel pin in `kernel/source.env`, or a `stable` index date).
- Steps to reproduce, or a proof of concept. Keep proofs of concept minimal and do not run them against systems you do not own.
- Your assessment of impact: who is affected, what an attacker gains, and whether it needs local access, network access or user interaction.
- Whether the issue is already public anywhere, and whether you plan to disclose it.

## What to expect

| Step | Target time |
|------|-------------|
| Acknowledgement of your report | 3 business days |
| Initial triage: confirm, reject or ask for more detail | 7 days |
| Fix for a critical issue in a shipped kernel, `pkgmgr`, or signing infrastructure | 72 hours from confirmation |
| Fix for other confirmed issues | Next scheduled release, or 30 days, whichever is sooner |
| Public advisory | When a fix is available in `stable`, or after 90 days, whichever is first |

These are targets, not guarantees. If we will miss one, we tell you and explain why.

We credit reporters in the advisory unless you ask us not to.

## Scope

**In scope**

- The Poop Linux kernel fork and its build configuration (`kernel/`).
- Packages and recipes in this repository, and the component repos we pin: `musl-poop`, `poopsuite`, `poop` (`pkgmgr`).
- The package and index formats, signature verification and the trust roots in `keyring/`.
- The installer (`installer/`), the initramfs (`initramfs/`), and the default configuration in `etc/` and `init/services/`.
- The CI and publish pipeline, if a flaw could let an attacker change released artifacts or reach signing secrets.
- The release artifacts: ISOs, packages and indexes published to `stable` or `testing`.

**Out of scope**

- Vulnerabilities that exist only upstream and are not made worse by us. Report those to the upstream project as well (for the Linux kernel, the upstream kernel security team). Tell us in your report so we can track our exposure.
- Problems in software that a user installs themselves from a source other than our repositories.
- Denial of service from local root, or from a physical attacker who already has the machine.
- Social engineering of maintainers, and spam or reports generated without verification.
- Reports from automated scanners that have not been checked by a person.

## Supported versions

Poop Linux is pre-alpha. Until the first stable release, only the current `main` branch and the `testing` channel receive security fixes. After the first stable release, this table will list supported releases.

| Version | Supported |
|---------|-----------|
| `main` / `testing` | Yes |
| `stable` (first release pending) | — |

## Keys and signing

- Package and index signatures use Ed25519, verified by `pkgmgr`. Trust roots are in `keyring/`. Only public keys live in the repository.
- The master signing key is kept offline. The signing subkey lives in CI secrets. Key custody and rotation are described in [`CONTRIBUTING.md`](CONTRIBUTING.md) §15.
- If you believe a signing key is compromised, report it as above and mark the report **"signing key"** in the title. We treat those reports as the highest priority.
- Current public key fingerprints will be published here and in `keyring/` once the first key is generated. Verify any key against both places.

## Safe harbour

We will not pursue legal action against good-faith security research that follows this policy: testing your own systems or our test instances, avoiding privacy violations and data destruction, stopping when you reach proof of impact, and reporting privately first.

## Advisories and changes

Security fixes are recorded in [`CHANGELOG.md`](CHANGELOG.md) under a "Security" heading, with the affected versions and the fixed version. Advisories are published through GitHub Security Advisories on the repository.
