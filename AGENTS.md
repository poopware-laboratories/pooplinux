# AGENTS.md

Instructions for AI coding agents working in the **Poop Linux** repository. This file is the canonical agent guide. Tool-specific files (for example `CLAUDE.md`) import it and add tool-specific notes only.

If anything here conflicts with a direct instruction from a maintainer in the current task, follow the maintainer and mention the conflict in your final report.

---

## 1. What this project is

Poop Linux is a **from-scratch** x86_64 Linux distribution. Every package is built from upstream source by recipes in this repo. The kernel is built from our fork, `poopware-laboratories/linux` (a fork of `torvalds/linux`), pinned by commit. Packages are installed and upgraded by **our own package manager**, `pkgmgr` (working name). The only edition is **`tty`**: no desktop, text console only.

archiso is used in exactly one place: the **live bootstrap environment** on the ISO. It supplies the host toolchain for the first build stage and runs our installer, which bootstraps the target system from our repository. Arch's packages are never part of the target system.

The full design, utility choices and decision log are in [`ARCHITECTURE.md`](ARCHITECTURE.md). **Read it before making any structural change.** Process and contributor rules are in [`CONTRIBUTING.md`](CONTRIBUTING.md). Do not duplicate them here. Link to them.

Status: early foundations. The kernel fork is currently identical to upstream. Most directories in `ARCHITECTURE.md` §2.4 do not exist yet. Check the tree before assuming a path exists.

---

## 2. Repository map

| Path | Owns | Notes |
|------|------|-------|
| `ARCHITECTURE.md` | Design, utility choices, ADR log, milestones | Source of truth for *why* |
| `AGENTS.md` / `CLAUDE.md` | Agent instructions | `CLAUDE.md` imports this file |
| `CONTRIBUTING.md` | Human contributor workflow | Source of truth for *how humans work here* |
| `LICENSE` | BSD-3-Clause | Applies to our code, recipes and docs |
| `CHANGELOG.md` | Release notes | Keep a Changelog format (to be created) |
| `Makefile` | The only supported build entry point | Targets in §5 |
| `kernel/` | `source.env`, kernel config fragments, `build.sh` | `source.env` is the only place the kernel SHA lives |
| `pkgmgr/` | Our package manager, C11, with its tests | Own README documents the `.pkginfo` format |
| `recipes/` | One directory per package: `recipe.toml` + `build.sh` | The whole system is built from here |
| `bootstrap/` | Stage definitions and `order.txt` | Build order is a plain file, checked by CI |
| `sandbox/` | Build sandbox configuration | Chroot and namespace helpers |
| `initramfs/` | Initramfs generator and `init` script | busybox-based |
| `etc/` | Default `/etc` templates | Never machine-specific |
| `init/services/` | runit service directories | |
| `keyring/` | **Public** keys only | Private keys never enter the repo |
| `repo/` | Index generation, signing scripts, channel rules | Scripts must not contain key material |
| `installer/` | TTY installer (POSIX sh + dialog) | |
| `iso/` | archiso profile for the live environment | Bootstrap-host packages only |
| `branding/` | Text and metadata for the system | No third-party marks |
| `tests/` | Lint, `pkgmgr` scenario tests, reproducibility, boot tests | |
| `docs/decisions/` | ADRs (`NNNN-title.md`) | One per accepted decision |
| `.github/workflows/` | CI | Changes here need extra care; see §7 |

---

## 3. Invariants — never violate these

These are hard rules. If a task seems to need one broken, stop and ask a maintainer.

1. **Pin the kernel by full commit SHA.** Never point a recipe at a branch. The only kernel pin is `kernel/source.env`. Do not vendor the kernel tree and do not add it as a submodule.
2. **Never commit secrets or keys.** This includes Ed25519 private keys, Secure Boot private keys, CI tokens, `.pem`/`.key` files, and anything matching `*secret*`. Signing keys live in CI secrets or on offline hardware. Public keys belong in `keyring/`.
3. **Every source is hash-verified.** A recipe's `[[source]]` must have a `sha256` (or stronger). Git sources must be pinned by full commit SHA. Never fill in a hash by copying a failed build's output without checking the upstream source yourself.
4. **Never weaken signature checks.** `pkgmgr` refuses unsigned or badly signed packages and indexes. Do not add flags, configs or code paths that skip verification in release configurations.
5. **Never push to `main` or `master`, never force-push, never merge a PR yourself.** Work on a branch. Open PRs as drafts unless a maintainer asks otherwise.
6. **Never ship a half-built system.** If a recipe in `bootstrap/order.txt` fails, or a package listed in the live environment is missing, the build fails. Do not remove it from the list to make the build pass without a maintainer's approval.
7. **Do not add non-free firmware or proprietary blobs to default recipes.** Opt-in recipes are fine if they are clearly labelled.
8. **Do not use third-party trademarks or logos** in `branding/` or any user-visible asset.
9. **Do not change `kernel/config/base.config` by hand to make a build pass.** Changes go in a fragment under `kernel/config/fragments/`, or they are a deliberate regeneration reviewed by a maintainer.
10. **Do not disable tests, lint checks, boot gates or the reproducibility report** to get a green build. If a check is wrong, fix the check in its own commit and explain why.
11. **Do not add install-time scripts to `pkgmgr` packages.** Packages in v0 carry no scripts that run as root during install. Configuration goes in templates under `etc/` or service directories.
12. **Do not introduce a dependency on Arch packages, `makepkg`, `pacman` or systemd into the target system.** The live environment may use archiso tooling. The installed system may not.
13. **Every new source file gets the BSD-3-Clause SPDX header** (`SPDX-License-Identifier: BSD-3-Clause`), unless it is a generated file or a vendored file that carries its own license.

---

## 4. How to work here

### 4.1 Before you start

1. Read `ARCHITECTURE.md` sections relevant to your task. At minimum: §2.4 (contracts), §3 (the subsystem you touch), §5 (utility choices) and §6 (ADRs).
2. Run `git status` and `git log --oneline -n 10`. Check whether the work already exists on another branch.
3. Check the file or directory you intend to touch. Do not assume a path in the design doc exists yet.
4. If your change touches a contract in §2.4, or accepts or reverses a decision in §5/§6, plan an ADR. Ask the maintainer whether it should be a separate PR.

### 4.2 Isolation

- Code changes happen in a **git worktree** on a feature branch, not in a shared checkout. Under Claude Code, use `.claude/worktrees/<name>` (ignored by git, see `.gitignore`).
- Keep one logical change per branch. Do not bundle `pkgmgr` changes with recipe changes, or kernel changes with docs.

### 4.3 Making changes

- **`pkgmgr` (C11):** `-std=c11 -Wall -Wextra -Werror`. No new runtime dependency without an ADR. Parsers take untrusted input (archives, indexes), so every parser change needs a test and, where it touches archive or index parsing, a fuzz target.
- **Recipes:** `recipe.toml` must validate against the contract in `ARCHITECTURE.md` §2.4. `build.sh` defines only `prepare`, `build`, `check` and `install`. It writes only into `$DESTDIR`. It reads no host files except declared inputs.
- **Shell (installer, scripts, `build.sh`):** `set -eu` (plus `pipefail` where bash is used). Quote variables. Pass `shellcheck` and `shfmt` (`make lint`). Installer scripts stay POSIX `sh` unless an ADR says otherwise.
- **Kernel config:** make changes as small fragments. After any change, run the drift check and commit the expected result.
- **Bootstrap order:** add a recipe to `bootstrap/order.txt` only after its dependencies are above it. CI rejects violations.
- **Docs:** Markdown with the same heading style as the existing docs. Keep examples runnable.

### 4.4 Verification before you claim done

Run the checks that apply and report their real output. Do not say "tests pass" unless you ran them.

| Change type | Minimum verification |
|-------------|----------------------|
| Docs only | Internal links and anchors resolve; no stale paths |
| Shell script | `shellcheck` and `shfmt -d` clean |
| `pkgmgr` | Unit tests (`make test-pkgmgr`) pass; compile with `-Werror`; scenario tests pass when they exist |
| Recipe | `recipe.toml` validates; `make recipe-check R=<name>` passes; build in the sandbox when the target exists |
| Kernel config | Drift check clean |
| Installer or `iso/` | ISO build (`make iso`) and boot test, or state that they were not run |
| Anything that boots | `make test-boot` passes, or you state it was not run and why |

If a check cannot run in your environment (no root, no KVM, no sandbox), say so explicitly. Do not present a skipped check as a passed one.

### 4.5 Benchmarks and performance claims

Any claim that a change makes something faster, smaller, or lighter needs measurements:

- Measure before and after on the same machine, with the same inputs.
- Run at least 5 repetitions. Report the median and the min–max range.
- Report every workload you measured, not only the best one.
- Put benchmark results in the **chat response** as a table (one row per workload, columns: before median (min–max), after median (min–max), change). Also include them in the PR description.
- Do not claim a performance win without numbers. If you cannot measure it, say that.

### 4.6 Commits and PRs

- Use **Conventional Commits**: `type(scope): summary`, for example `feat(pkgmgr): verify index signature before parsing`.
- Keep the subject under 72 characters. Use the body to explain *why*.
- When you are an AI agent writing a commit, end the commit message with the trailer `Co-Authored-By: <model name> <noreply@anthropic.com>`. Do not add other attribution lines.
- PR descriptions follow `.github/PULL_REQUEST_TEMPLATE.md` (to be created). For AI-authored PRs made with Claude Code, end the description with the line `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

---

## 5. Commands

The `Makefile` arrives in Phase 0 (see `ARCHITECTURE.md` §9). Until it exists, run the underlying tool directly and say so in your report.

| Target | What it does | Phase |
|--------|--------------|-------|
| `make lint` | shellcheck, shfmt, yamllint, editorconfig-checker, recipe and bootstrap-order checks, SPDX header check | 0 |
| `make test-pkgmgr` | Build and run `pkgmgr` unit tests with sanitizers | 1 |
| `make fuzz-pkgmgr` | Run the archive and index fuzz targets for a fixed time | 1 |
| `make recipe-check R=<name>` | Validate one `recipe.toml` and its source hashes | 0 |
| `make fetch R=<name>` | Download and hash-verify a recipe's sources into the cache | 2 |
| `make build R=<name>` | Build one recipe in the sandbox and pack it | 2 |
| `make bootstrap-stage STAGE=1\|2\|3\|4` | Build one bootstrap stage | 2–4 |
| `make kernel` | Build `linux-poop` from the pinned SHA | 3 |
| `make kernel-config-check` | Run `olddefconfig` and fail on drift | 3 |
| `make repo` | Build and sign the `testing` index from built packages | 4 |
| `make iso` | Build the `tty` live ISO with `mkarchiso` (root or privileged container) | 5 |
| `make test-boot ISO=<path>` | Boot the ISO in QEMU+OVMF and check for the success marker | 5 |
| `make test-install` | Run the installer in QEMU against a blank disk, then boot the result | 5 |
| `make clean` | Remove `out/`, `work/` and the build cache for the local tree | 0 |

Build outputs go in `out/` and `work/`. Never commit them.

---

## 6. Conventions

- **Package names:** lowercase, hyphens allowed. Distro-owned packages use the `poop-` prefix (for example `poop-firewall`). Kernel packages are `linux-poop` and `linux-poop-headers`.
- **Versions:** the package `version` is the upstream version. `release` is the distro revision for the recipe.
- **Package files:** `<name>-<version>-<release>-<arch>.pkg.tar.zst` with a detached `.sig`.
- **Repo channels:** `testing` and `stable`. Promotion copies signed files; it never rebuilds.
- **Kernel tags:** `poop-v<kver>-<n>` in the fork.
- **ISO names:** `poop-tty-<YYYY.MM.DD>-x86_64.iso`.
- **Editions:** one, `tty`. Do not add an edition without an ADR.
- **Language and tone:** plain, direct text. The project name is playful; keep it out of security advisories, error messages and package descriptions.

---

## 7. Sensitive areas (extra caution)

Changes in these areas need a maintainer review, even if CI is green:

- `.github/workflows/` (CI runs with access to signing secrets)
- `keyring/` and `repo/` (trust roots and publish logic)
- `pkgmgr/src/` code that verifies signatures, parses archives or writes to the root filesystem
- `kernel/source.env` (changes which kernel ships)
- `kernel/config/` (security-relevant options such as lockdown and module signing)
- `bootstrap/stage0/` (seed hashes)
- `sandbox/` (build isolation)
- `installer/` (it touches disks)

When you change one of these, state the risk in your PR description and tag it for review.

---

## 8. What to report at the end of a task

Give a short, factual report:

1. What changed, with file paths.
2. Which checks you ran, with their real results. Name any check you did not run.
3. Any decision you made that a maintainer should confirm.
4. Open items and the next command to run, if there is one.

Do not claim that the kernel boots, that a stage builds, that a package is signed, or that the ISO works unless you ran the step and saw the result.
