# AGENTS.md

Instructions for AI coding agents working in the **Poop Linux** repository. This file is the canonical agent guide. Tool-specific files (for example `CLAUDE.md`) import it and add tool-specific notes only.

If anything here conflicts with a direct instruction from a maintainer in the current task, follow the maintainer and mention the conflict in your final report.

---

## 1. What this project is

Poop Linux is an x86_64 Linux distribution. Its kernel is built from our fork, `poopware-laboratories/linux` (a fork of `torvalds/linux`). Everything above the kernel uses the Arch Linux packaging model: PKGBUILDs, `makepkg`, `pacman`, and `archiso` for ISOs. Our own signed repositories (`poop-testing`, `poop-stable`) sit beside the upstream Arch repositories.

The full design, including the utility choices and decision log, is in [`ARCHITECTURE.md`](ARCHITECTURE.md). **Read it before making any structural change.** Process and contributor rules are in [`CONTRIBUTING.md`](CONTRIBUTING.md). Do not duplicate those rules here. Link to them.

Status: early foundations. The kernel fork is currently identical to upstream. Most directories in `ARCHITECTURE.md` §2.4 do not exist yet. Check the tree before assuming a path exists.

---

## 2. Repository map

| Path | Owns | Notes |
|------|------|-------|
| `ARCHITECTURE.md` | Design, utility choices, ADR log, milestones | Source of truth for *why* |
| `AGENTS.md` / `CLAUDE.md` | Agent instructions | `CLAUDE.md` imports this file |
| `CONTRIBUTING.md` | Human contributor workflow | Source of truth for *how humans work here* |
| `CHANGELOG.md` | Release notes | Keep a Changelog format |
| `Makefile` | The only supported build entry point | Targets listed in §5 |
| `kernel/` | `linux-poop` PKGBUILD, `source.env`, kernel config fragments | `source.env` is the only place the kernel SHA lives |
| `packages/` | One directory per `poop-*` package | Each has a PKGBUILD and any installed files |
| `profiles/` | archiso profiles (`minimal`, `desktop`) | Valid archiso layout |
| `installer/calamares/` | Calamares config and branding | Desktop edition only |
| `repo/` | `pacman.conf` for CI and users; channel rules | Never contains private keys |
| `scripts/` | Bash build helpers | Must pass `shellcheck` |
| `tests/` | Lint checks and QEMU boot tests | Boot tests gate promotion |
| `docs/decisions/` | ADRs (`NNNN-title.md`) | Create one for each accepted decision |
| `.github/workflows/` | CI | Changes here need extra care; see §7 |

---

## 3. Invariants — never violate these

These are hard rules. If a task seems to need one broken, stop and ask a maintainer.

1. **Pin the kernel by full commit SHA.** Never point a PKGBUILD at a branch name. The only kernel pin is `kernel/source.env`. Do not vendor the kernel tree and do not add it as a submodule.
2. **Never commit secrets or keys.** This includes GPG private keys, `sbctl` private keys, CI tokens, `.pem`/`.key` files, and anything matching `*secret*`. Signing keys live in CI secrets or on offline hardware. Public keys belong in `poop-keyring`.
3. **Never use `SKIP` checksums** for tarballs or archives. `SKIP` is only allowed for git sources pinned by commit SHA. Never fill in a checksum by copying the output of a failed build without verifying the upstream source.
4. **Never weaken signature checks.** `SigLevel` must stay `Required DatabaseOptional`. Do not add `Never`, `Optional` or `TrustAll` to any `pacman.conf`.
5. **Never push to `main` or `master`, never force-push, never merge a PR yourself.** Work on a branch. Open PRs as drafts unless a maintainer asks otherwise.
6. **Never ship a half-populated profile.** If a package listed in a profile is not in an accepted repo, the build must fail. Do not remove the package from the list to make the build pass without a maintainer's approval.
7. **Do not add non-free firmware or proprietary blobs to default packages.** Opt-in packages are fine if they are clearly labelled.
8. **Do not use Arch trademarks or logos** in `poop-branding` or any user-visible asset.
9. **Do not change `kernel/config/base.config` by hand to make a build pass.** Changes go in a fragment under `kernel/config/fragments/`, or they are a deliberate regeneration reviewed by a maintainer.
10. **Do not disable tests, lint checks or boot gates** to get a green build. If a check is wrong, fix the check in its own commit and explain why.

---

## 4. How to work here

### 4.1 Before you start

1. Read `ARCHITECTURE.md` sections relevant to your task. At minimum: §2.4 (contracts), §5 (utility choices), and §6 (ADRs).
2. Run `git status` and `git log --oneline -n 10`. Check whether the work already exists on another branch.
3. Check the file or directory you intend to touch. Do not assume a path in the design doc exists yet.
4. If your change touches a contract in §2.4, or accepts or reverses a decision in §5/§6, plan an ADR. Ask the maintainer whether it should be a separate PR.

### 4.2 Isolation

- Code changes happen in a **git worktree** on a feature branch, not in a shared checkout. Under Claude Code, use `.claude/worktrees/<name>` (ignored by git, see `.gitignore`).
- Keep one logical change per branch. Do not bundle kernel changes with packaging or docs.

### 4.3 Making changes

- **PKGBUILDs:** follow the Arch packaging guidelines. Include `pkgver`, `pkgrel`, a correct `license`, `arch=('x86_64')`, checksums, and a `package()` function that only writes into `$pkgdir`. Run `namcap` on the result.
- **Shell:** `set -euo pipefail` at the top of every script. Quote variables. Pass `shellcheck` and `shfmt` (`make lint`).
- **Kernel config:** make changes as small fragments. After any change, run the `olddefconfig` drift check and commit the expected result.
- **archiso profiles:** keep `profiledef.sh` minimal. Put packages in `packages.x86_64` one per line, sorted. Put files in `airootfs/` with the exact target path.
- **Docs:** Markdown with the same heading style as the existing docs. Put the status line at the top of design docs. Keep examples runnable.

### 4.4 Verification before you claim done

Run the checks that apply and report their real output. Do not say "tests pass" unless you ran them.

| Change type | Minimum verification |
|-------------|----------------------|
| Docs only | Links resolve (`make lint` when it exists), no stale file paths |
| Shell script | `shellcheck` and `shfmt -d` clean |
| PKGBUILD | `namcap` clean; `makepkg --verifysource` succeeds; builds in a clean chroot when the build target exists |
| Kernel config | `olddefconfig` drift check clean |
| Profile or `pacman.conf` | Profile builds with `make iso PROFILE=<name>` when the target exists; otherwise say it was not run |
| Anything that boots | `make test-boot` passes, or you state that it was not run and why |

If a check cannot run in your environment (for example, no privileged container or no KVM), say so explicitly in your report. Do not present a skipped check as a passed one.

### 4.5 Benchmarks and performance claims

Any claim that a change makes something faster, smaller, or lighter needs measurements. Follow these rules:

- Measure before and after on the same machine, with the same inputs.
- Run at least 5 repetitions. Report the median and the min–max range.
- Report every workload you measured, not only the best one.
- Put benchmark results in the **chat response** as a table (one row per workload, columns: before median (min–max), after median (min–max), change). Also include them in the PR description.
- Do not claim a performance win without numbers. If you cannot measure it, say that.

### 4.6 Commits and PRs

- Use **Conventional Commits**: `type(scope): summary`, for example `feat(kernel): add fragment for AppArmor defaults`.
- Keep the subject under 72 characters. Use the body to explain *why*.
- When you are an AI agent writing a commit, end the commit message with the trailer the repo requires: `Co-Authored-By: <model name> <noreply@anthropic.com>`. Do not add other attribution lines.
- PR descriptions follow `.github/PULL_REQUEST_TEMPLATE.md` (to be created). For AI-authored PRs, end the description with the line `🤖 Generated with [Claude Code](https://claude.com/claude-code)` when Claude Code made the change.

---

## 5. Commands

These targets are the supported interface. The `Makefile` is planned for Phase 0 (see `ARCHITECTURE.md` §9). Until it exists, run the underlying tool directly and say so in your report.

| Target | What it does | Planned phase |
|--------|--------------|---------------|
| `make lint` | shellcheck, shfmt, yamllint, editorconfig-checker, namcap on all PKGBUILDs | 0 |
| `make kernel` | Build `linux-poop` from the pinned SHA in a clean chroot | 1 |
| `make kernel-config-check` | Run `olddefconfig` and fail on drift | 1 |
| `make pkg PKG=<name>` | Build one `poop-*` package in a clean chroot | 2 |
| `make repo` | Build the signed `poop-testing` repo from built packages | 2 |
| `make iso PROFILE=minimal\|desktop` | Build an ISO with `mkarchiso` (needs root or privileged container) | 3 |
| `make test-boot ISO=<path>` | Boot the ISO in QEMU+OVMF and check for the success marker | 3 |
| `make clean` | Remove `out/`, `work/`, `pkg/`, `src/`, built packages | 0 |

Build outputs go in `out/` and `work/`. Never commit them.

---

## 6. Conventions

- **Naming:** `poop-` prefix for distro packages. Kernel packages are `linux-poop` and `linux-poop-headers`. Repo channels are `poop-testing` and `poop-stable`.
- **Versions:** kernel `pkgver` follows upstream, converted to Arch style (`7.4rc1`). The Poop revision is `pkgrel`.
- **Kernel tags:** `poop-v<kver>-<n>` in the fork.
- **ISO names:** `poop-<edition>-<YYYY.MM.DD>-x86_64.iso`.
- **Editions:** `minimal` (CLI) and `desktop` (graphical). Do not add a third edition without an ADR.
- **Language and tone:** plain, direct text. The project name is playful; keep it out of security advisories, error messages and package descriptions.

---

## 7. Sensitive areas (extra caution)

Changes in these areas need a maintainer review, even if CI is green:

- `.github/workflows/` (CI runs with access to signing secrets)
- `repo/` and `packages/poop-keyring/` (trust roots)
- `kernel/source.env` (changes which kernel ships)
- `kernel/config/` (security-relevant options such as LSMs and lockdown)
- `packages/poop-firewall/` (default network policy)
- `scripts/` that touch the signing step or the publish step

When you change one of these, state the risk in your PR description and tag it for review.

---

## 8. What to report at the end of a task

Give a short, factual report:

1. What changed, with file paths.
2. Which checks you ran, with their real results. Name any check you did not run.
3. Any decision you made that a maintainer should confirm.
4. Open items and the next command to run, if there is one.

Do not claim the kernel boots, the ISO builds, or a package is signed unless you ran the step and saw the result.
