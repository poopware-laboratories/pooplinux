# Contributing to Poop Linux

Thanks for helping. This document explains how to set up a build environment, how to propose a change, what we check before merge, and how releases happen. The design is in [`ARCHITECTURE.md`](ARCHITECTURE.md). If you are an AI agent, read [`AGENTS.md`](AGENTS.md) too. Its hard rules apply to everyone.

---

## Table of contents

1. [Code of conduct](#1-code-of-conduct)
2. [What we accept](#2-what-we-accept)
3. [Before you start](#3-before-you-start)
4. [Setting up a development environment](#4-setting-up-a-development-environment)
5. [The kernel fork](#5-the-kernel-fork)
6. [Recipes](#6-recipes)
7. [The package manager (`pkgmgr`)](#7-the-package-manager-pkgmgr)
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
| Bug fixes in `pkgmgr`, recipes, installer, scripts | New recipe stages or changes to `bootstrap/order.txt` |
| Documentation fixes and clarifications | Changes to kernel config defaults |
| Kernel config fragments with a clear reason | Kernel patches that are not in upstream |
| New recipes for software that fits the design | Changes to `keyring/`, `repo/`, signing or CI secrets |
| Tests, fuzz targets and lint checks | Changes that alter a contract in `ARCHITECTURE.md` §2.4 |
| Hardening patches for base packages | Install-time scripts, new edition, new architecture |

If it is in the second column, open an issue or a draft PR first. We would rather talk about a 30-line plan than review a 1,000-line surprise.

## 3. Before you start

1. Search open issues and PRs for the same change.
2. Read the parts of `ARCHITECTURE.md` that cover your area. §3 explains each subsystem, §5 lists the utility choices and §6 is the ADR log.
3. For anything in the second column above, open an issue with: the problem, the proposed change, the alternatives you considered, and what you would revisit later.

## 4. Setting up a development environment

### 4.1 Requirements

- A **Linux host** with `git`, a C11 compiler, `make`, `shellcheck`, `shfmt`, `yamllint`, `editorconfig-checker`, `python3` (for the repo's lint scripts), and `qemu-system-x86` with `edk2-ovmf` for boot tests.
- For bootstrap builds and ISO builds: root (or a privileged container), loop devices, about **80 GiB** of free disk, and `archiso` for `mkarchiso`.
- KVM is strongly recommended for boot tests. Without it, boot tests run very slowly.

### 4.2 First steps

```bash
git clone git@github.com:poopware-laboratories/pooplinux.git
cd pooplinux
make lint                 # start here; no build needed
make test-pkgmgr          # once pkgmgr/ exists
```

Until a `make` target exists for your area, run the underlying tool directly and say so in your PR.

### 4.3 Containers

We recommend a containerised build environment for bootstrap and ISO work, so your host stays clean. A `containers/` definition is planned for Phase 0. Until then, use a privileged Linux container that meets the requirements in §4.1.

## 5. The kernel fork

The kernel source is **not** in this repository. It lives in [`poopware-laboratories/linux`](https://github.com/poopware-laboratories/linux), a fork of `torvalds/linux`.

### 5.1 Changing the kernel version

1. Pick the upstream commit or tag you want (usually an upstream release, or a stable point release).
2. Make sure the fork contains it. Merge upstream in the fork, not here.
3. Update `kernel/source.env`:
   - `POOP_KERNEL_SHA` to the **full** 40-character commit SHA.
   - `POOP_KERNEL_VERSION` to the matching version string.
4. Run `make kernel-config-check`. If it fails, regenerate the config deliberately and commit the result with the reason.
5. Build with `make kernel`. Boot-test it. Open a PR. Include the old and new SHA in the description.

Never point a recipe at a branch. CI rejects it.

### 5.2 Adding a kernel option

Put the change in a new file under `kernel/config/fragments/`, named for its purpose, for example `lockdown-integrity.config`. Keep one purpose per fragment. Add a comment at the top that says why the option exists.

### 5.3 Adding a kernel patch

A patch belongs in the **fork**, not here. Open the change against `poopware-laboratories/linux`, then bump the pin in this repo. Every Poop-specific patch needs a short justification: why it is not upstream, and what would make it removable.

## 6. Recipes

A recipe is one package's build description. A package is built from upstream source; nothing is taken from another distribution.

### 6.1 Layout

```
recipes/<name>/
├── recipe.toml     metadata, sources with sha256, dependencies, stage
├── build.sh        prepare / build / check / install functions
└── files/          optional: templates or patches the build uses (hash-listed in recipe.toml)
```

The contract for `recipe.toml` and `build.sh` is in `ARCHITECTURE.md` §2.4.

### 6.2 Rules

- Every `[[source]]` has a `sha256`. Git sources are pinned by full commit SHA, never by branch or tag name.
- `build.sh` defines only `prepare`, `build`, `check` (optional) and `install`. `install` writes only into `$DESTDIR`.
- Builds run in the sandbox with **no network**. Anything the build needs must be declared in `recipe.toml` and fetched in the fetch phase.
- Declare every build and runtime dependency. Missing dependencies fail the sandbox build, so they do not go unnoticed.
- Do not ship install-time scripts. If the package needs setup, ship a template under `etc/` or a service directory under `init/services/`.
- Use the base hardening flags defined in `ARCHITECTURE.md` §3.3 unless the recipe documents why it cannot.
- `license` in `recipe.toml` must match the upstream license. Use an SPDX identifier.

### 6.3 Adding a recipe

1. Check that the software is actually needed. Every recipe is a maintenance commitment.
2. Create `recipes/<name>/` with `recipe.toml` and `build.sh`.
3. Add the recipe to `bootstrap/order.txt` at a position after all its dependencies.
4. Run `make recipe-check R=<name>`, then `make build R=<name>` in the sandbox.
5. Add a line to `CHANGELOG.md` under "Unreleased".

### 6.4 Changing a bootstrap stage

Stage changes can invalidate everything above them. A PR that moves a recipe between stages, or changes a stage1 toolchain recipe, must say which later recipes need a rebuild, and must run the stage rebuild in CI before review.

## 7. The package manager (`pkgmgr`)

`pkgmgr` lives in `pkgmgr/`, written in C11. It is the most security-sensitive code in the project, because it reads untrusted archives and indexes and writes to the root filesystem.

### 7.1 Rules for `pkgmgr` changes

- Build with `-std=c11 -Wall -Wextra -Werror`. CI also builds with AddressSanitizer and UndefinedBehaviorSanitizer.
- No new runtime dependency without an ADR. The current set is libcurl, libarchive, libzstd, SQLite and libsodium (see `ARCHITECTURE.md` §3.1).
- Any change to archive parsing, index parsing or path handling needs a unit test, and a fuzz target update where applicable.
- Signature verification must run **before** any file is written. A change that moves or weakens that order is rejected.
- Never add a flag that installs unsigned packages in a release configuration.

### 7.2 Package file format

Changes to `.pkginfo` or the archive layout are format changes. They need an ADR, a version field bump, and a compatibility note in `pkgmgr/README.md`.

## 8. Branches, commits and pull requests

### 8.1 Branches

- Branch names: `<type>/<short-description>`, for example `fix/pkgmgr-index-rollback` or `feat/recipe-linux-headers`.
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

- **types:** `feat`, `fix`, `docs`, `build`, `ci`, `refactor`, `test`, `chore`, `perf`, `security`, `revert`
- **scopes:** `pkgmgr`, `kernel`, `recipe`, `bootstrap`, `sandbox`, `initramfs`, `installer`, `iso`, `repo`, `keyring`, `ci`, `docs`, or a recipe name
- Use a body for anything non-trivial. Explain *why*, not just *what*.
- Sign your commits if you can (`git commit -S`). Signed commits are recommended for contributors and required for maintainers' commits to `main`.

### 8.3 Pull requests

- Open PRs against `main`. Mark them **draft** until CI is green and the description is complete.
- Use the template at `.github/PULL_REQUEST_TEMPLATE.md` (to be created in Phase 0). It asks for:
  - what changed and why
  - which checks you ran, with results
  - whether the change touches a sensitive area (`AGENTS.md` §7)
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
| Any PR | `make lint`, commit-message check, PR template check, SPDX header check | Hosted CI |
| `pkgmgr` change | Unit tests, `-Werror` build, ASan/UBSan run, fuzz smoke test for parsers | Hosted CI |
| Recipe change | `recipe-check`, sandbox build, install of the result into a stage root | Self-hosted runner |
| Bootstrap order or stage change | Stage rebuild for affected stages, reproducibility report | Self-hosted runner |
| Kernel change | Drift check, kernel build, QEMU boot to busybox shell | Self-hosted runner, KVM |
| Installer or `iso/` change | ISO build, boot test, install test in QEMU | Self-hosted runner, KVM |
| Keyring or repo change | Signature verification, install from a clean repo, two-maintainer review | Self-hosted runner + review |
| Docs only | Link and anchor check, Markdown lint | Hosted CI |

**Boot test success marker:** the boot test passes when the serial console prints the marker defined in `tests/boot/` (for example, `POOP_BOOT_OK`) within the time limit. Do not change the marker to make a test pass.

## 11. Architecture decisions (ADRs)

Significant decisions get an ADR in `docs/decisions/`.

- **When to write one:** anything that changes a contract in `ARCHITECTURE.md` §2.4, moves a *Proposed* decision to *Accepted* (or back), adds a runtime dependency to `pkgmgr`, changes the package or index format, or reverses an earlier ADR.
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

We acknowledge reports within **3 business days** and aim to ship a fix within **72 hours** for critical issues in shipped kernels, `pkgmgr`, or signing infrastructure. We credit reporters who want credit.

Kernel vulnerabilities that exist upstream should also be reported to the upstream kernel security team. Tell us in your report.

## 14. Releases

Releases follow the channels in `ARCHITECTURE.md` §2.4.

1. **Testing:** every green build of `main` that passes the bootstrap, boot and install tests is published to the `testing` channel.
2. **Stable promotion:** a build is promoted to `stable` when:
   - kernel changes have spent at least **7 days** in testing,
   - the install test and boot test pass for the `tty` edition, and
   - the changelog is updated.
3. **ISOs:** built from `stable` only. Each ISO release gets a changelog entry and SHA-256 checksums, signed with the release key.
4. **Rollback:** a bad release is rolled back by re-pointing `stable` at the previous signed index. Announce the rollback in the changelog and in the release notes.

A release manager is named for each release in the changelog.

## 15. Signing keys and custody

- **Master key:** offline, on hardware tokens. Two custodians hold it, and a third holds an encrypted backup. It is used only to sign the signing subkey and keyring updates.
- **Signing subkey:** lives in CI secrets. It signs packages and repo indexes. It expires and is rotated on a schedule (every 12 months, or immediately if compromised).
- **Secure Boot keys:** generated on the release machine. The private keys never leave that machine. Only the public keys ship, in `keyring/` and on the ISO.
- **Rotation:** announced in advance, with the new public key in `keyring/` for at least one release before the old key is removed.
- **Compromise:** report it using §13. We revoke the key, publish a new keyring, and publish an advisory. Users who installed packages signed by the compromised key are told how to verify their systems.

Never commit a private key, a token, or a secret, even to a branch you plan to delete.

## 16. AI-assisted contributions

AI tools are welcome as long as the human who opens the PR has read and understood the change, can explain it, and has run the checks.

- Say in the PR description that AI tools were used. Name the tool if you can.
- AI-generated code gets the same review as any other code. Do not expect reviewers to accept output they have not been asked to check.
- Do not paste secrets, private keys or unpublished vulnerability details into AI tools.
- AI agents follow `AGENTS.md`. Their commits carry the attribution trailer described there.

## 17. Licensing

- **Our code, recipes and documentation:** **EUPL-1.2**, as stated in the root [`LICENSE`](LICENSE) file.
- **New source files** carry the SPDX header:

  ```
  SPDX-License-Identifier: EUPL-1.2
  ```

  Generated files and vendored third-party files keep the license they came with.
- **Kernel source (`poopware-laboratories/linux`):** GPL-2.0-only, as upstream. The EUPL-1.2 appendix lists GPL-2.0 as a compatible licence, so EUPL-licensed code and the kernel can be combined.
- **Upstream software built by recipes:** each keeps its upstream license. The `license` field in `recipe.toml` must match it.
- By contributing, you agree that your contribution is licensed under EUPL-1.2, unless the file you change states another license that applies to it.

## 18. Maintainers

Maintainers are listed in `MAINTAINERS.md` (to be created in Phase 0), along with their area of ownership. For a sensitive area, `CODEOWNERS` will name the owners once the file exists.

Until those files exist, open an issue and tag the maintainers who set up the repo.
