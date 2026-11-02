# Contributing to Poop Linux

Thanks for helping. This document explains how to set up a build environment, how to propose a change, what we check before merge, and how releases happen. The design is in [`ARCHITECTURE.md`](ARCHITECTURE.md). If you are an AI agent, read [`AGENTS.md`](AGENTS.md) too. Its hard rules apply to everyone. Security reports go through [`SECURITY.md`](SECURITY.md), never through public issues.

---

## Table of contents

1. [Code of conduct](#1-code-of-conduct)
2. [What we accept](#2-what-we-accept)
3. [Before you start](#3-before-you-start)
4. [Setting up a development environment](#4-setting-up-a-development-environment)
5. [The kernel fork](#5-the-kernel-fork)
6. [Recipes](#6-recipes)
7. [Component repositories](#7-component-repositories)
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

Everyone taking part in this project follows the [Code of Conduct](CODE_OF_CONDUCT.md). Report conduct concerns privately to a maintainer listed in [`MAINTAINERS.md`](MAINTAINERS.md).

## 2. What we accept

| Welcome | Please discuss first |
|---------|----------------------|
| Bug fixes in recipes, installer, scripts, initramfs | New recipe stages or changes to `bootstrap/order.txt` |
| Documentation fixes and clarifications | Changes to kernel config defaults |
| Kernel config fragments with a clear reason | Kernel patches that are not in upstream |
| New recipes for software that fits the design | Changes to `keyring/`, `repo/`, signing or CI secrets |
| Tests, fuzz targets and lint checks | Changes that alter a contract in `ARCHITECTURE.md` §2.4 |
| Hardening patches for base packages | Install-time scripts, new edition, new architecture |
| Bug reports for `pkgmgr`, `poopsuite` or `musl-poop` (file them in those repos) | Feature work in `pkgmgr`, `poopsuite` or `musl-poop` before a design issue exists |

If it is in the second column, open an issue or a draft PR first. We would rather talk about a 30-line plan than review a 1,000-line surprise.

## 3. Before you start

1. Search open issues and PRs for the same change, in this repo and in the component repos.
2. Read the parts of `ARCHITECTURE.md` that cover your area. §3 explains each subsystem, §5 lists the utility choices and §6 is the ADR log.
3. For anything in the second column above, open an issue with: the problem, the proposed change, the alternatives you considered, and what you would revisit later.

## 4. Setting up a development environment

### 4.1 Requirements

- A **Linux host** with `git`, a C compiler, `make`, `shellcheck`, `shfmt`, `yamllint`, `editorconfig-checker`, `python3` (for the repo's lint scripts), and `qemu-system-x86` with `edk2-ovmf` for boot tests.
- For bootstrap and ISO builds: root (or a privileged container), loop devices, about **80 GiB** of free disk, and `archiso` for `mkarchiso`.
- KVM is strongly recommended for boot tests. Without it, boot tests run very slowly.

### 4.2 First steps

```bash
git clone git@github.com:poopware-laboratories/pooplinux.git
cd pooplinux
make lint                 # start here; no build needed
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

A recipe is one package's build description. Most packages are built from upstream source. Our own components are pinned by commit (§7).

### 6.1 Layout

```
recipes/<name>/
├── recipe.toml     metadata, sources with sha256 or commit SHA, dependencies, stage
├── build.sh        prepare / build / check / install functions
└── files/          optional: templates or patches the build uses (hash-listed in recipe.toml)
```

The contract for `recipe.toml` and `build.sh` is in `ARCHITECTURE.md` §2.4.

### 6.2 Rules

- Every archive `[[source]]` has a `sha256`. Git sources are pinned by full commit SHA, never by branch or tag name.
- `build.sh` defines only `prepare`, `build`, `check` (optional) and `install`. `install` writes only into `$DESTDIR`.
- Builds run in the sandbox with **no network**. Anything the build needs must be declared in `recipe.toml` and fetched in the fetch phase.
- Declare every build and runtime dependency. Missing dependencies fail the sandbox build, so they do not go unnoticed.
- Do not ship install-time scripts. If the package needs setup, ship a template under `etc/` or a poopsuite service definition under `init/services/`.
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

## 7. Component repositories

Three core components live in their own repositories and are pinned here by commit SHA, in their recipes:

| Component | Repo | Recipe that pins it | What it is |
|-----------|------|---------------------|------------|
| Package manager | `poopware-laboratories/poop` | `recipes/poop/` | `pkgmgr`: installs, upgrades, verifies, rolls back |
| Init and boot stack | `poopware-laboratories/poopsuite` | `recipes/poopsuite/` | PID 1, rc, logger, user tools |
| C library | `poopware-laboratories/musl-poop` | `recipes/musl-poop/` | Our musl fork, focused on performance |

### 7.1 Where to make a change

- **Code changes go to the component repo**, in a branch and PR there, following that repo's own rules. Do not copy component code into this repo.
- **Pin bumps happen here.** A bump PR changes `commit` in the recipe, states the old and new SHA, and runs the integration tests in §10.
- **Language of `pkgmgr` is open** (ARCHITECTURE Q4). Until the `poop` repo declares one, do not add build tooling for it to this repo.

### 7.2 Rules for component changes

- **`pkgmgr`:** signature verification must run before any file is written. A change that moves or weakens that order is rejected. Archive and index parsers take untrusted input, so they need tests and fuzz coverage in the `poop` repo. Never add a flag that installs unsigned packages in a release configuration.
- **`poopsuite`:** PID 1 runs as root, so every change to process supervision, mounts or signal handling needs a review by a sensitive-area owner (`AGENTS.md` §7).
- **`musl-poop`:** performance claims need benchmarks following §12. Changes that alter security-relevant behaviour (hardening, memory allocation, locale or DNS code paths) need a security review. Upstream musl changes are merged on the schedule in ARCHITECTURE Q11.

### 7.3 Package file format

Changes to the `.pkginfo` format or the archive layout are format changes. They need an ADR in `poop`, a version field bump, and a compatibility note in the `poop` repo's documentation.

## 8. Branches, commits and pull requests

### 8.1 Branches

- Branch names: `<type>/<short-description>`, for example `fix/pkg-index-rollback` or `feat/recipe-linux-headers`.
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
- **scopes:** `kernel`, `recipe`, `bootstrap`, `sandbox`, `initramfs`, `installer`, `iso`, `repo`, `keyring`, `ci`, `docs`, `pin`, or a recipe name
- Use a body for anything non-trivial. Explain *why*, not just *what*.
- Sign your commits if you can (`git commit -S`). Signed commits are recommended for contributors and required for maintainers' commits to `main`.

### 8.3 Pull requests

- Open PRs against `main`. Mark them **draft** until CI is green and the description is complete.
- Fill in the template at `.github/PULL_REQUEST_TEMPLATE.md`. It asks for:
  - what changed and why
  - which checks you ran, with results
  - whether the change touches a sensitive area (`AGENTS.md` §7)
  - whether it changes a contract or decision in `ARCHITECTURE.md`
- Keep PRs small. Target under 400 changed lines where you can. Split large changes into a sequence of PRs.
- A PR that changes behaviour must say how you verified it.
- Do not describe an unfixed vulnerability in a PR. Report it through [`SECURITY.md`](SECURITY.md).

## 9. Review

- **No approving review is required to merge.** A PR merges when every required CI check passes: `docs`, `lint`, `secrets` and `policy` (`.github/workflows/ci.yml`). CI is the gate, so it is strict: shellcheck, actionlint, SPDX headers, secret scanning, Conventional Commits titles and attribution-footer checks all run on every PR.
- Maintainers may still review and comment. Sensitive areas (`AGENTS.md` §7) should be called out in the PR description so that a reviewer can look at them.
- Reviewers look at correctness first, then reproducibility, then security, then style.
- Authors respond to every comment: fix it, or explain why not, and resolve the thread only after the reviewer agrees.
- If a review takes more than 7 days with no reply, ping the maintainers' channel.
- Maintainers may close PRs that stall for 30 days without activity. You can reopen them.

## 10. Testing matrix

| Change | Required checks | Where they run |
|--------|-----------------|----------------|
| Any PR | `make lint`, commit-message check, PR template check, SPDX header check | Hosted CI |
| Recipe change | `recipe-check`, sandbox build, install of the result into a stage root | Self-hosted runner |
| Pin bump (`poop`, `poopsuite`, `musl-poop`) | Scenario tests in `tests/pkgmgr/`, stage1 hello-world, boot test if the change touches PID 1 or the C library; benchmarks if the bump claims a speed or size gain | Self-hosted runner |
| Bootstrap order or stage change | Stage rebuild for affected stages, reproducibility report | Self-hosted runner |
| Kernel change | Drift check, kernel build, QEMU boot to busybox shell | Self-hosted runner, KVM |
| Installer or `iso/` change | ISO build, boot test, install test in QEMU | Self-hosted runner, KVM |
| Keyring or repo change | Signature verification, install from a clean repo, two-maintainer review | Self-hosted runner + review |
| Docs only | Link and anchor check, Markdown lint | Hosted CI |

**Boot test success marker:** the boot test passes when the serial console prints the marker defined in `tests/boot/` (for example, `POOP_BOOT_OK`) within the time limit. Do not change the marker to make a test pass.

## 11. Architecture decisions (ADRs)

Significant decisions get an ADR in `docs/decisions/`.

- **When to write one:** anything that changes a contract in `ARCHITECTURE.md` §2.4, moves a *Proposed* or *Open* decision to *Accepted* (or back), adds a runtime dependency to a component, changes the package or index format, or reverses an earlier ADR.
- **Component-level decisions** (for example the `pkgmgr` language, Q4) are recorded in the component repo's own ADR log, and this repo's `ARCHITECTURE.md` is updated to match.
- **How:** copy the next number, `NNNN-short-title.md`. Use these sections: *Status*, *Context*, *Decision*, *Consequences*, *Alternatives*.
- **Status values:** `Proposed`, `Open`, `Accepted`, `Superseded by NNNN`, `Rejected`.
- **Update `ARCHITECTURE.md`** in the same PR, so the design doc and the ADR do not disagree.

## 12. Benchmarks and performance claims

If your PR or pin bump says something is faster, smaller, or lighter, it needs measurements:

- Measure before and after on the same machine, with the same inputs.
- Run at least 5 repetitions and report the **median** and the **min–max** range.
- Report **every** workload you measured, not only the best one.
- Put the results in the PR description as a table: one row per workload, with columns for before, after and change.
- A performance claim without numbers gets removed from the PR description before review.

## 13. Security issues

**Do not open a public issue, PR or discussion for a security vulnerability.**

Follow [`SECURITY.md`](SECURITY.md). Use GitHub's private vulnerability reporting on `poopware-laboratories/pooplinux`. It sets out what to include, the response targets (acknowledgement within 3 business days, fixes for critical issues within 72 hours of confirmation), scope, and how advisories are published.

Vulnerabilities that exist upstream should also be reported to the upstream project, for the Linux kernel to the upstream kernel security team. Tell us in your report.

## 14. Releases

Releases follow the channels in `ARCHITECTURE.md` §2.4.

1. **Testing:** every green build of `main` that passes the bootstrap, boot and install tests is published to the `testing` channel.
2. **Stable promotion:** a build is promoted to `stable` when:
   - kernel changes have spent at least **7 days** in testing,
   - the install test and boot test pass for the `tty` edition, and
   - the changelog is updated.
3. **ISOs:** built from `stable` only. Each ISO release gets a changelog entry and SHA-256 checksums, signed with the release key.
4. **Rollback:** a bad release is rolled back by re-pointing `stable` at the previous signed index. Announce the rollback in the changelog and in the release notes.

A release manager is named for each release in `CHANGELOG.md`. Security entries go under the **Security** heading of the release they ship in.

## 15. Signing keys and custody

- **Master key:** offline, on hardware tokens. Two custodians hold it, and a third holds an encrypted backup. It is used only to sign the signing subkey and keyring updates.
- **Signing subkey:** lives in CI secrets. It signs packages and repo indexes. It expires and is rotated on a schedule (every 12 months, or immediately if compromised).
- **Secure Boot keys:** generated on the release machine. The private keys never leave that machine. Only the public keys ship, in `keyring/` and on the ISO.
- **Rotation:** announced in advance, with the new public key in `keyring/` for at least one release before the old key is removed.
- **Compromise:** report it using [`SECURITY.md`](SECURITY.md) and mark the report "signing key". We revoke the key, publish a new keyring, and publish an advisory. Users who installed packages signed by the compromised key are told how to verify their systems.

Never commit a private key, a token, or a secret, even to a branch you plan to delete.

## 16. AI-assisted contributions

AI tools are welcome as long as the human who opens the PR has read and understood the change, can explain it, and has run the checks.

- Say in the PR description that AI tools were used. Name the tool if you can.
- AI-generated code gets the same review as any other code. Do not expect reviewers to accept output they have not been asked to check.
- Do not paste secrets, private keys or unpublished vulnerability details into AI tools.
- AI agents follow `AGENTS.md`. Their commits carry only the `Co-Authored-By` trailer described there. Commits and PR descriptions never carry a "Generated with" footer or a session link.

## 17. Licensing

- **Our code, recipes and documentation:** **BSD-3-Clause**, as stated in the root [`LICENSE`](LICENSE) file.
- **New source files** carry the SPDX header:

  ```
  SPDX-License-Identifier: BSD-3-Clause
  ```

  Generated files and vendored third-party files keep the license they came with.
- **Kernel source (`poopware-laboratories/linux`):** GPL-2.0-only, as upstream. BSD-3-Clause is GPL-compatible, so our BSD-licensed code and the kernel can be combined.
- **Component repos** (`poop`, `poopsuite`, `musl-poop`): each repo states its own license. Check it before contributing. `musl-poop` is a fork of musl and keeps musl's license terms for the parts it inherits.
- **Upstream software built by recipes:** each keeps its upstream license. The `license` field in `recipe.toml` must match it.
- By contributing, you agree that your contribution is licensed under BSD-3-Clause, unless the file you change states another license that applies to it.

## 18. Maintainers

Maintainers, the areas they own and how to reach them are listed in [`MAINTAINERS.md`](MAINTAINERS.md). Sensitive areas are mapped to owners in `.github/CODEOWNERS`, which stays commented out until the handles are filled in.
