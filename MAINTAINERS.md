# Maintainers

This file lists who maintains Poop Linux, what they own, and how to reach them. Keep it current. A maintainer who steps back moves to the "Former maintainers" list rather than being deleted, so their past reviews stay traceable.

Contact details are not stored here. Use the channel named in the table, or GitHub mentions. Do not put personal email addresses or phone numbers in this file.

## Current maintainers

| Name / handle | Areas owned | Notes |
|---------------|-------------|-------|
| *(to be filled in by maintainers)* | Project lead, release management | Named release manager for each release in `CHANGELOG.md` |
| *(to be filled in)* | `pkgmgr` integration, bootstrap | |
| *(to be filled in)* | Kernel (`kernel/`), `poopware-laboratories/linux` | |
| *(to be filled in)* | Signing and keyring (`keyring/`, `repo/`) | Custodian of the offline master key (CONTRIBUTING §15) |
| *(to be filled in)* | Installer and ISO (`installer/`, `iso/`) | |
| *(to be filled in)* | Security response (`SECURITY.md`) | Receives private vulnerability reports |

Every area above needs at least two maintainers before the first public release, so that a single absence does not block a security fix or a release.

## Ownership of sensitive areas

Sensitive areas (`AGENTS.md` §7) need two reviews, one of which comes from the owner of that area. `.github/CODEOWNERS` will mirror this table once the handles are filled in.

## Former maintainers

*(none yet)*

## Channels

- Day-to-day discussion: an issue or a draft PR on `poopware-laboratories/pooplinux`.
- Security: see [`SECURITY.md`](SECURITY.md). Never use a public channel for a vulnerability.
- Conduct concerns: see [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).
