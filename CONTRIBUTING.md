# Contributing to Poop Linux

Thanks for helping. This document explains how to set up a build environment, how to propose a change, what we check before merge, and how releases happen. The design is in [`ARCHITECTURE.md`](ARCHITECTURE.md). If you are an AI agent, read [`AGENTS.md`](AGENTS.md) too. Its hard rules apply to everyone.

---

## Table of contents

1. [Code of conduct](#1-code-of-conduct)
2. [What we accept](#2-what-we-accept)
3. [Before you start](#3-before-you-start)
4. [Setting up a development environment](#4-setting-up-a-development-environment)
5. [The kernel fork](#5-the-kernel-fork)
6. [Packages](#6-packages)
7. [Profiles and ISOs](#7-profiles-and-isos)
8. [Branches, commits and pull requests](#8-branches-commits-and-pull-requests)
9. [Review](#9-review)
10. [Testing matrix](#10-testing-matrix)
11. [Architecture decisions (ADRs)](#11-architecture-decisions-adrs)
12. [Benchmarks and performance claims](#12-benchmarks-and-performance-claims)
13. [Security issues](#13-security-issues)
14. [Releases](#14-releases)
15. [Signing keys and custody](#15-signing-keys-and-custody)
16. [AI-assisted contributions](#16-ai-assisted-contributions)
17. [Licensing](#17-licensing)
18. [Maintainers](#18-maintainers)

---

## 1. Code of conduct

Be direct, be kind, and assume good faith. Criticise code and designs, not people. Maintainers may remove comments or contributors who repeatedly ignore this.

A full Code of Conduct (Contributor Covenant) is a Phase 0 deliverable. Until it lands, this section applies.

## 2. What we accept

| Welcome | Please discuss first |
|---------|----------------------|
| Bug fixes in packaging, scripts, profiles, installer config | New editions, new architectures, new init systems |
| Documentation fixes and clarifications | Changes to kernel config defaults |
| Kernel config fragments with a clear reason | Kernel patches that are not in upstream |
| New `poop-*` packages that fit the design | Changes to `poop-keyring`, signing or CI secrets |
| Tests and lint checks | Changes that alter a contract in `ARCHITECTURE.md` §2.4 |
| Translations of user-facing text (once the framework exists) | Adding non-free firmware or proprietary software to defaults |

If it is in the second column, open an issue or a draft PR first. We would rather talk about a 30-line plan than review a 1,000-line surprise.

## 3. Before you start

1. Search open issues and PRs for the same change.
2. Read the parts of `ARCHITECTURE.md` that cover your area. §5 (utility choices) and §6 (ADR log) explain most "why is it like this" questions.
3. For anything in the second column above, open an issue with: the problem, the proposed change, the alternatives you considered, and what you would revisit later.

## 4. Setting up a development environment

### 4.1 Requirements

- An **Arch Linux** host (or an Arch container) for building packages and ISOs. Other distributions can run lint and documentation checks only.
- `base-devel`, `git`, `archiso`, `namcap`, `shellcheck`, `shfmt`, `yamllint`, `editorconfig-checker`, `qemu-desktop`, `edk2-ovmf`
- About **60 GiB** of free disk for kernel builds and ISOs. Put `work/` on fast storage if you can.
- Root access (or a privileged container) for `mkarchiso`. Loop devices must be available.
- KVM for boot tests is strongly recommended. Without it, boot tests run very slowly.

### 4.2 First build

```bash
git clone git@github.com:poopware-laboratories/pooplinux.git
cd pooplinux
make lint                 # no build needed; start here
make kernel-config-check  # when Phase 1 has landed
```

Until `make` targets exist for your area, follow the commands in `AGENTS.md` §5 directly, and mention in your PR which ones you could not run.

### 4.3 Containers

We recommend a containerised build environment so your host stays clean. A `containers/` setup is planned for Phase 0. Until then, use a privileged Arch container with the requirements from §4.1.

## 5. The kernel fork

The kernel source is **not** in this repository. It lives in [`poopware-laboratories/linux`](https://github.com/poopware-laboratories/linux), which is a fork of `torvalds/linux`.

### 5.1 Changing the kernel version

1. Pick the upstream commit or tag you want (usually an upstream release, or a stable point release).
2. Make sure the fork contains it. Merge upstream in the fork, not here.
3. Update `kernel/source.env`:
   - `POOP_KERNEL_SHA` to the **full** 40-character commit SHA.
   - `POOP_KERNEL_VERSION` to the matching `pkgver` form.
4. Run `make kernel-config-check`. If it fails, regenerate the config deliberately and commit the result with the reason.
5. Build with `make kernel`. Boot-test it. Open a PR. Include the old and new SHA in the description.

Never point the PKGBUILD at a branch. CI rejects it.

### 5.2 Adding a kernel option

Put the change in a new file under `kernel/config/fragments/`, named for its purpose, for example `apparmor-defaults.config`. Keep one purpose per fragment. Add a comment at the top that says why the option exists.

### 5.3 Adding a kernel patch

A patch belongs in the **fork**, not here. Open the change against `poopware-laboratories/linux`, then bump the pin in this repo. The only exception is a patch that must be applied to the PKGBUILD for packaging reasons. Those go in `kernel/patches/` and need a maintainer's approval.

Every Poop-specific patch needs a short justification: why it is not upstream, and what would make it removable.

## 6. Packages

### 6.1 Layout

```
packages/<name>/
├── PKGBUILD
├── .SRCINFO            (generated: makepkg --printsrcinfo > .SRCINFO)
└── <files installed by the package>
```

### 6.2 Rules

- Follow the Arch packaging guidelines. Use `pkgver`, `pkgrel`, `pkgdesc`, `url`, `license`, `arch=('x86_64')`, and proper `depends`/`makedepends`.
- Every source has a checksum (`sha256sums`). `SKIP` is only allowed for git sources pinned by a commit SHA.
- `package()` writes only into `$pkgdir`.
- Run `namcap PKGBUILD` and `namcap <built>.pkg.tar.zst`. Fix errors. Justify any warnings you keep in the PR.
- Regenerate `.SRCINFO` whenever the PKGBUILD changes. CI checks that it matches.
- Do not depend on a package from outside the repos we use (`core`, `extra`, `multilib`, `poop-*`).

### 6.3 Adding a package

1. Check that no upstream package already does the job. Prefer reusing it.
2. Create `packages/<name>/` with a PKGBUILD. Name it `poop-<something>` unless it is a kernel package.
3. Add it to the appropriate meta-package (`poop-base` or `poop-desktop`) if it belongs in an edition.
4. Add a line to `CHANGELOG.md` under "Unreleased".

### 6.4 Overriding an upstream package

Overrides are the most expensive kind of change. An override needs:

- An entry in `repo/overrides.md` with the upstream package name, the version we track, and the reason.
- A plan for removing the override.
- A maintainer's approval (see ADR-003).

## 7. Profiles and ISOs

- Each profile in `profiles/` is a valid archiso profile.
- Keep `packages.x86_64` sorted, one package per line, with no duplicates. CI checks both.
- Files in `airootfs/` must go to the exact target path. No symlinks to paths outside the image.
- Do not hard-code mirrors in profile files. Use the repo definitions in `repo/`.
- Every change to a profile should come with a boot test run, or a note explaining why one was not run.

## 8. Branches, commits and pull requests

### 8.1 Branches

- Branch names: `<type>/<short-description>`, for example `fix/firewall-ipv6-default` or `feat/kernel-apparmor-fragment`.
- Work from `main`. Rebase on `main` before opening the PR, or merge `main` in if a rebase would be painful for reviewers.
- Do not push to `main`. Do not force-push a branch that someone else reviewed without saying so in the PR.

### 8.2 Commits

We use [Conventional Commits](https://www.conventionalcommits.org/).

```
type(scope): short summary in the imperative, under 72 characters

Why the change is needed. What alternatives were considered.
Any follow-up work.

Refs: #123
```

- **types:** `feat`, `fix`, `docs`, `build`, `ci`, `refactor`, `test`, `chore`, `perf`, `revert`
- **scopes:** `kernel`, `pkg`, `profile`, `installer`, `repo`, `ci`, `docs`, or a package name such as `poop-firewall`
- Use a body for anything non-trivial. Explain *why*, not just *what*.
- Sign your commits if you can (`git commit -S`). Signed commits are recommended, not required, for contributors. Maintainers' commits to release branches are required to be signed.

### 8.3 Pull requests

- Open PRs against `main`. Mark them **draft** until CI is green and the description is complete.
- Use the template at `.github/PULL_REQUEST_TEMPLATE.md` (to be created in Phase 0). It asks for:
  - what changed and why
  - which checks you ran, with results
  - whether the change touches any *sensitive area* (`AGENTS.md` §7)
  - whether it changes a contract or decision in `ARCHITECTURE.md`
- Keep PRs small. Target under 400 changed lines where you can. Split large changes into a sequence of PRs.
- A PR that changes behaviour must say how you verified it.

## 9. Review

- Every PR needs **one approving review** from a maintainer. PRs touching a sensitive area need **two**, one of whom owns that area.
- Reviewers look at correctness first, then reproducibility, then security, then style.
- Authors respond to every comment: fix it, or explain why not, and resolve the thread only after the reviewer agrees.
- If a review takes more than 7 days with no reply, ping the maintainers' channel.
- Maintainers may close PRs that stall for 30 days without activity. You can reopen them.

## 10. Testing matrix

| Change | Required checks | Where they run |
|--------|-----------------|----------------|
| Any PR | `make lint`, commit-message check, PR template check | Hosted CI |
| PKGBUILD change | `namcap`, `makepkg --verifysource`, clean-chroot build, `.SRCINFO` match | Self-hosted Arch runner |
| Kernel change | Config drift check, kernel build, boot test | Self-hosted Arch runner, KVM |
| Profile or installer change | ISO build, boot test, install test (minimal, then desktop) | Self-hosted Arch runner, KVM |
| Repo or keyring change | Signature verification, install from a clean repo, two-maintainer review | Self-hosted Arch runner + review |
| Docs only | Link check, Markdown lint | Hosted CI |

**Boot test success marker:** the boot test passes when the serial console prints the marker defined in `tests/boot/` (for example, `POOP_BOOT_OK`) within the time limit. Do not change the marker to make a test pass.

## 11. Architecture decisions (ADRs)

Significant decisions get an ADR in `docs/decisions/`.

- **When to write one:** anything that changes a contract in `ARCHITECTURE.md` §2.4, moves a *Proposed* decision to *Accepted* (or back), adds a utility or dependency with lasting impact, or reverses an earlier ADR.
- **How:** copy the next number, `NNNN-short-title.md`. Use these sections: *Status*, *Context*, *Decision*, *Consequences*, *Alternatives*.
- **Status values:** `Proposed`, `Accepted`, `Superseded by NNNN`, `Rejected`.
- **Update `ARCHITECTURE.md`** in the same PR, so the design doc and the ADR do not disagree.

## 12. Benchmarks and performance claims

If your PR says something is faster, smaller, or lighter, it needs measurements:

- Measure before and after on the same machine, with the same inputs.
- Run at least 5 repetitions and report the **median** and the **min–max** range.
- Report **every** workload you measured, not only the best one.
- Put the results in the PR description as a table: one row per workload, with columns for before, after and change.
- A performance claim without numbers gets removed from the PR description before review.

## 13. Security issues

**Do not open a public issue for a security vulnerability.**

Report it privately through GitHub's private vulnerability reporting on `poopware-laboratories/pooplinux`, or by email to the security contact listed in `SECURITY.md` (to be created in Phase 0). Include:

- the affected component and version
- steps to reproduce, or a proof of concept
- your assessment of impact

We acknowledge reports within **3 business days** and aim to ship a fix within **72 hours** for critical issues in shipped kernels or signing infrastructure. We credit reporters who want credit.

Kernel vulnerabilities that exist upstream should also be reported to the upstream kernel security team. Tell us in your report.

## 14. Releases

Releases follow the channels in `ARCHITECTURE.md` §2.4.

1. **Testing:** every green build of `main` that passes the boot test is published to `poop-testing`.
2. **Stable promotion:** a build is promoted to `poop-stable` when:
   - kernel changes have spent at least **7 days** in testing, and
   - the boot test and install test pass for both editions, and
   - the changelog is updated.
3. **ISOs:** built from `poop-stable` only. Each ISO release gets a changelog entry and SHA-256 checksums, signed with the release key.
4. **Rollback:** a bad release is rolled back by re-pointing `poop-stable` at the previous snapshot. Announce the rollback in the changelog and in the release notes.

A release manager is named for each release in the changelog.

## 15. Signing keys and custody

- **Master key:** offline, on hardware tokens. Two custodians hold it, and a third holds an encrypted backup. It is used only to sign the signing subkey and the keyring package.
- **Signing subkey:** lives in CI secrets. It signs packages and repo databases. It expires and is rotated on a schedule (every 12 months, or immediately if compromised).
- **Secure Boot keys:** generated with `sbctl` on the release machine. The private keys never leave that machine. Only the public keys ship, in `poop-keyring` and on the ISO.
- **Rotation:** announced in advance, with the new public key in `poop-keyring` for at least one release before the old key is removed.
- **Compromise:** report it using §13. We revoke the key, publish a new keyring, and publish an advisory. Users who installed packages signed by the compromised key are told how to verify their systems.

Never commit a private key, a token, or a secret, even to a branch you plan to delete.

## 16. AI-assisted contributions

AI tools are welcome as long as the human who opens the PR has read and understood the change, can explain it, and has run the checks.

- Say in the PR description that AI tools were used. Name the tool if you can.
- AI-generated code gets the same review as any other code. Do not expect reviewers to accept output they have not been asked to check.
- Do not paste secrets, private keys or unpublished vulnerability details into AI tools.
- AI agents follow `AGENTS.md`. Their commits carry the attribution trailer described there.

## 17. Licensing

- **Kernel:** GPL-2.0, as upstream. The fork's license terms apply to the kernel source.
- **Packaging and scripts in this repo:** MIT *(Proposed; not yet confirmed by maintainers, see the Licensing row in `ARCHITECTURE.md` §5)*. Add the license header to new files if the existing files have one.
- **Packages:** each package keeps its upstream license. The PKGBUILD's `license` field must match it.
- By contributing, you agree that your contribution is licensed under the license that applies to the file you change.

## 18. Maintainers

Maintainers are listed in `MAINTAINERS.md` (to be created in Phase 0), along with their area of ownership. For a sensitive area, `CODEOWNERS` will name the owners once the file exists.

Until those files exist, open an issue and tag the maintainers who set up the repo.
