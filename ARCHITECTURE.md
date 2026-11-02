# Poop Linux — Architecture

Status: **Draft v0.3** (2026-11-02). Revised after maintainer input:

- From-scratch distribution, TTY-only, bootstrapped from an archiso live environment (v0.2).
- Init is **poopsuite** (our own), the C library is **musl-poop** (our musl fork), and the package manager `pkgmgr` lives in its own repo, **poopware-laboratories/poop**, with its language still open (v0.3).
- Project code, recipes and docs are licensed under **EUPL-1.2** (v0.2).

Decisions marked *Accepted* are binding for v0.x. *Proposed* decisions need maintainer sign-off before the milestone that depends on them. Open items are collected in §8.

This document is the system design for the distribution and for this repository. It answers four questions: what we build, how the pieces fit, which utilities we chose and why, and what we will revisit as the project grows. Process rules live in [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`AGENTS.md`](AGENTS.md).

---

## 0. Summary

Poop Linux is an x86_64 Linux system built from source by its own recipes. Its core components are ours:

| Component | Where it lives | Status |
|-----------|----------------|--------|
| Kernel (`linux-poop`) | [`poopware-laboratories/linux`](https://github.com/poopware-laboratories/linux), a fork of `torvalds/linux`, pinned by commit | Identical to upstream today (`0 ahead / 0 behind`, head `Linux 7.4-rc1`) |
| C library | [`poopware-laboratories/musl-poop`](https://github.com/poopware-laboratories/musl-poop), our musl fork, focused on performance | Pinned in `recipes/musl-poop/` |
| Init, rc, logger, user tools | [`poopware-laboratories/poopsuite`](https://github.com/poopware-laboratories/poopsuite), a self-contained C boot stack | Pinned in `recipes/poopsuite/` |
| Package manager (`pkgmgr`) | [`poopware-laboratories/poop`](https://github.com/poopware-laboratories/poop), "package manager for pooplinux" | Language to be decided (Q4). Pinned in `recipes/poop/` |
| Everything else | Upstream source, built by recipes in this repo | — |

Packages are installed and upgraded by `pkgmgr`, which verifies signatures and keeps a transactional local database. archiso is used in exactly one place: the **live bootstrap environment** that a user boots from the ISO. It supplies the host toolchain for the first build stage, and it runs our installer, which bootstraps the target system from our repository. Arch's packages are never part of the target system.

The desktop is out of scope for v0. The only edition is **`tty`**, which boots to a text console.

---

## 1. Requirements

### 1.1 Functional requirements

| ID | Requirement |
|----|-------------|
| F1 | Build every system package from source, using recipes in this repo, or pin one of our own component repos. |
| F2 | Build the kernel (`linux-poop`) from a **pinned commit** of `poopware-laboratories/linux`. |
| F3 | Install, remove, upgrade and downgrade packages with `pkgmgr`, with signature checks and an atomic transaction model. |
| F4 | Build a bootable x86_64 live ISO with archiso. The live environment bootstraps a target system from our repository. |
| F5 | Install to disk on UEFI firmware, with ext4 root and a FAT ESP. |
| F6 | Upgrade installed systems with `pkgmgr`, and keep the previous kernel bootable after a kernel upgrade. |
| F7 | Build the system from its own packages (self-hosting). Rebuilding the whole set with the system's own tools must succeed. |
| F8 | Make release artifacts reproducible from the repo plus pinned inputs, wherever the upstream tools allow it. |
| F9 | Provide a text-console environment with networking, time sync, a firewall and an SSH server as optional packages. |
| F10 | Use `poopsuite` as PID 1 and as the service supervisor. |

### 1.2 Non-functional requirements

These are **proposed targets**. Each one gets measured in CI before we claim it.

| Area | Target | Measured by |
|------|--------|-------------|
| Full bootstrap time (stage0 to ISO) | < 6 h on a 16-core runner, warm caches | CI job timing |
| Kernel build time | < 30 min on a 16-core runner | CI job timing |
| `pkgmgr` install of 200 packages from a local repo | < 60 s excluding downloads | Benchmark (`AGENTS.md` §4.5) |
| C library performance | Measured against the upstream musl baseline on a fixed benchmark set | Benchmark (`AGENTS.md` §4.5) |
| Boot to login prompt (QEMU, OVMF, 2 vCPU, 2 GiB) | < 20 s | Boot smoke test |
| Installed base system size | < 1.5 GiB | Image audit |
| Critical kernel CVE to shipped fix | < 72 h after upstream fix lands | Release log |
| Package integrity | 100 % of installed files match signed metadata | `pkgmgr verify` in tests |
| Reproducibility | Same recipe + same inputs → same package file hashes, for packages where the upstream build allows it | Rebuild check |
| Licensing | Every shipped component redistributable. Non-free firmware is opt-in. | License audit |

### 1.3 Constraints and assumptions

- **Team (assumed):** 2–4 part-time maintainers. A from-scratch base, plus our own libc, init and package manager, is a large amount of work for that team. Scope is kept narrow (§9).
- **Timeline (assumed):** no hard date. The first milestone is "a text-console system bootstrapped from the live ISO and booted in QEMU".
- **Existing stack:** the kernel fork (GPL-2.0), our component repos (above), a GitHub organisation, and an empty `pooplinux` repo.
- **C library consequence:** the base is built on musl-poop, not glibc. Third-party software that needs glibc is not supported in the base. This is an accepted trade-off (ADR-013).
- **Bootstrap seed:** the first build stage uses the host toolchain in the archiso environment. This is an explicit trust dependency (§3.2, §7).
- **Hardware scope v0:** x86_64, UEFI only, TTY only.

---

## 2. High-level design

### 2.1 Component diagram

```
  torvalds/linux ───▶ poopware-laboratories/linux       (kernel fork, pinned by SHA)
  musl upstream  ───▶ poopware-laboratories/musl-poop   (libc, pinned by SHA)
                      poopware-laboratories/poopsuite   (init + rc + logger, pinned)
                      poopware-laboratories/poop        (pkgmgr, pinned)
                                   │
                                   ▼  pinned in recipes/ (or kernel/source.env)
┌───────────────────────────────────────────────────────────────────────────┐
│ recipes/   one directory per package: recipe.toml + build.sh               │
│            (toolchain, libc, base userland, linux-poop, poop, poopsuite)  │
└───────────────┬───────────────────────────────────────────────────────────┘
                │ built in a sandbox by `pkgmgr build` (bootstrap stages §3.2)
                ▼
┌───────────────────────────────┐        ┌──────────────────────────────────┐
│ Signed package repository     │◀──────▶│ repo/   index + signing tooling  │
│  index.zst (signed)           │        │   (publish job; subkey in CI)    │
│  *.pkg.tar.zst + *.sig        │        └──────────────────────────────────┘
└───────────────┬───────────────┘
                │ HTTPS, verified by pkgmgr (Ed25519 signatures)
                ▼
┌───────────────────────────────┐        ┌──────────────────────────────────┐
│ Live environment (archiso)    │───────▶│ Installed system (tty)           │
│  host toolchain (stage0 only) │ pkgmgr │  pkgmgr db, kernel, poopsuite    │
│  pkgmgr, installer, keyring   │ --root │  musl-poop, Limine, sshd (opt)   │
└───────────────────────────────┘        └──────────────────────────────────┘
                ▲
                │ mkarchiso (privileged, CI self-hosted runner)
                └── iso/  archiso profile (live environment only)
```

### 2.2 Software stack (what runs on an installed system)

```
  ┌────────────────────────────────────────────────────────────────┐
  │ Login        agetty on tty1–tty6 · login(1) · doas              │
  ├────────────────────────────────────────────────────────────────┤
  │ Services     poopsuite (PID 1, supervision, rc, logger, user)   │
  │              dhcpcd · iwd · chrony · nftables (poop-firewall)   │
  │              openssh (optional)                                 │
  ├────────────────────────────────────────────────────────────────┤
  │ Userspace    musl-poop (libc) · GNU coreutils · util-linux       │
  │              findutils · GNU sed/grep/gawk/tar · bash · make     │
  │              iproute2 · pkgmgr (package manager)                 │
  ├────────────────────────────────────────────────────────────────┤
  │ Kernel       linux-poop (poopware-laboratories/linux)            │
  │              + initramfs from our own generator (busybox)        │
  ├────────────────────────────────────────────────────────────────┤
  │ Boot         Limine (UEFI) → signed kernel EFI image             │
  │ Firmware     UEFI, optional Secure Boot with user keys           │
  └────────────────────────────────────────────────────────────────┘
```

### 2.3 Data flows

**Build flow (per release):**

```
kernel/source.env ──▶ fetch fork @ SHA ──▶ merge config fragments ──▶ build linux-poop
recipes/*/recipe.toml ──▶ fetch sources (hash-verified, cached) ──▶ build in sandbox
                                                          │
                                  pkgmgr pack ──▶ *.pkg.tar.zst + Ed25519 signature
                                                          │
                              repo publish: index.zst (signed) ──▶ testing channel
                                                          │
                       install test + boot test in QEMU ◀─┤
                                                          ▼ promote
                    iso/ profile + keyring + pkgmgr + installer ──▶ mkarchiso ──▶ ISO
```

**Install flow (from the live ISO):**

```
ISO boots (UEFI) ──▶ installer (POSIX sh + dialog, TTY)
  ──▶ partition: ESP (FAT32) + root (ext4)
  ──▶ pkgmgr --root /mnt --repo <url> install base linux-poop bootloader-limine ...
  ──▶ write fstab, hostname, users, locale, timezone, poopsuite service links
  ──▶ install Limine + signed kernel image to the ESP
  ──▶ reboot into the installed system
```

**Update flow (installed system):**

```
pkgmgr upgrade ──▶ fetch index (signature checked) ──▶ resolve transaction
  ──▶ download + verify all packages  ──▶ stage files  ──▶ conflict check against db
  ──▶ commit: swap files into place, record transaction, keep old package archives
  ──▶ if kernel changed: rebuild the boot entry, keep the previous kernel entry
```

### 2.4 Contracts

These are the interfaces other parts of the repo and external consumers depend on. Changing one needs an ADR (§6) and a CHANGELOG entry.

**Repository layout (target):**

```
pooplinux/
├── README.md                 entry point for humans
├── LICENSE                   EUPL-1.2 (our code, recipes, docs)
├── ARCHITECTURE.md           this document
├── AGENTS.md                 instructions for AI coding agents (canonical)
├── CLAUDE.md                 Claude Code entry point; imports AGENTS.md
├── CONTRIBUTING.md           contributor workflow
├── SECURITY.md               vulnerability reporting and response targets
├── CODE_OF_CONDUCT.md        conduct standards and enforcement
├── MAINTAINERS.md            maintainers, owned areas, channels
├── CHANGELOG.md              release notes (Keep a Changelog format)
├── Makefile                  the only supported build entry point
├── .gitignore
├── kernel/
│   ├── source.env            POOP_KERNEL_REPO, POOP_KERNEL_SHA, POOP_KERNEL_VERSION
│   ├── config/
│   │   ├── base.config       starting kernel config
│   │   └── fragments/*.config  Poop-specific options, merged on top of base
│   └── build.sh              kernel build driver (used by recipes/linux-poop)
├── recipes/                  one directory per package
│   ├── binutils/  gcc/  linux-headers/  ...   toolchain and base (bootstrap §3.2)
│   ├── musl-poop/            C library, pinned to a poopware-laboratories/musl-poop SHA
│   ├── poopsuite/            init, rc, logger, user; pinned to a poopsuite SHA
│   ├── poop/                 package manager; pinned to a poopware-laboratories/poop SHA
│   ├── linux-poop/           kernel package recipe (uses kernel/)
│   └── poop-firewall/  poop-base/  ...        distro-owned packages
├── bootstrap/
│   ├── stage0/               host-toolchain checks and seed hashes
│   ├── stage1/               temporary toolchain build order
│   └── order.txt             canonical build order for all recipes
├── sandbox/                  build sandbox configuration and helper scripts
├── initramfs/                initramfs generator and init script
├── etc/                      default /etc templates (never machine-specific)
├── init/services/            poopsuite service definitions (format defined by poopsuite)
├── keyring/                  PUBLIC keys only (poop-keyring source)
├── repo/                     index generation, signing scripts, channel rules
├── installer/                TTY installer (POSIX sh, dialog)
├── iso/                      archiso profile for the live environment
├── branding/                 os-release, issue, motd, boot splash text
├── tests/
│   ├── lint/                 recipe, shell, config checks
│   ├── pkgmgr/               scenario tests (install/remove/upgrade/rollback) in a stage root
│   ├── reproducibility/      rebuild-and-compare checks
│   └── boot/                 QEMU+OVMF boot and install tests
├── docs/
│   └── decisions/            ADRs (NNNN-title.md)
└── .github/workflows/        CI definitions
```

Note: `pkgmgr` source, its unit tests and its fuzz targets live in `poopware-laboratories/poop`. This repo pins a commit and tests the integrated result.

**External components and pins:**

| Component | Repo | Pinned in | Role | Owned by |
|-----------|------|-----------|------|----------|
| Kernel fork | `poopware-laboratories/linux` | `kernel/source.env` | Kernel | This project |
| C library | `poopware-laboratories/musl-poop` | `recipes/musl-poop/recipe.toml` | libc | This project (fork of musl) |
| Init and boot stack | `poopware-laboratories/poopsuite` | `recipes/poopsuite/recipe.toml` | PID 1, rc, logger, user tools | This project |
| Package manager | `poopware-laboratories/poop` | `recipes/poop/recipe.toml` | `pkgmgr` | This project |

Every pin is a full commit SHA. Bumping one is a PR in this repo that states the old and new SHA, and runs the integration tests (§10).

**Recipe contract (`recipes/<name>/recipe.toml`):**

```toml
name    = "coreutils"
version = "9.5"          # upstream version; release is the distro revision
release = 1
license = "GPL-3.0-or-later"
stage   = "base"         # bootstrap stage, see §3.2

[[source]]
url    = "https://ftp.gnu.org/gnu/coreutils/coreutils-9.5.tar.xz"
sha256 = "<64 hex chars, required>"

[depends]
build   = ["musl-poop", "make"]
runtime = ["musl-poop"]
```

A recipe that pins one of our own repos uses a git source with a commit SHA:

```toml
name    = "poop"
version = "<version of the poop repo at this SHA>"
release = 1
license = "EUPL-1.2"
stage   = "base"

[[source]]
url    = "https://github.com/poopware-laboratories/poop.git"
commit = "<40 hex chars, required; branch names are rejected>"
```

- `build.sh` defines the functions `prepare`, `build`, `check` (optional), `install`. It runs inside the sandbox with `$SRCDIR`, `$PKGDIR` and `$DESTDIR` set. Nothing is read from the host except declared inputs.
- Every archive source needs a `sha256`. Git sources are pinned by full commit SHA.

**Package file contract (`<name>-<version>-<release>-<arch>.pkg.tar.zst`):**

- A zstd-compressed tar archive.
- Contains a `.pkginfo` metadata file (key=value, documented in the `poop` repo), followed by the files, all with normalised owners (0:0), sorted entries and `SOURCE_DATE_EPOCH` mtimes.
- Accompanied by a detached Ed25519 signature `<file>.sig`, in minisign-compatible format.

**Repository index contract:**

- `index.zst` is a signed, compressed list of packages: name, version, release, arch, sha256, size, dependencies, provides and conflicts.
- Served from a static directory over HTTPS. Signatures are the trust root, so transport security is defence in depth and is not relied on alone.
- Channels are separate directories: `testing/` and `stable/`. Promotion is a copy of signed files, not a rebuild.

**Repository channels:**

| Channel | Purpose | Who consumes it | Promotion gate |
|---------|---------|-----------------|----------------|
| `testing` | Every successful CI build of `main` | Maintainers, early adopters | Automatic on green CI |
| `stable` | Default for the installer and for `pkgmgr upgrade` | Everyone | Install test + boot test pass; kernel changes spend 7 days in testing |

**Pinned kernel inputs (`kernel/source.env`):**

```bash
POOP_KERNEL_REPO="https://github.com/poopware-laboratories/linux.git"
POOP_KERNEL_SHA="6628e7d4c6b25c8d18f1345e3a20d21829aae7e4"   # Linux 7.4-rc1 at time of writing
POOP_KERNEL_VERSION="7.4rc1"
```

**Versioning:** packages use the upstream version plus a distro `release` number. Our own components use their repo's version at the pinned commit. Kernel git tags are `poop-v<kver>-<n>`. ISO names are `poop-tty-<YYYY.MM.DD>-x86_64.iso`.

---

## 3. Deep dive

### 3.1 Package manager (`pkgmgr`)

`pkgmgr` is developed in `poopware-laboratories/poop`. This section is the **behaviour specification** the `poop` repo must meet. It does not choose a language or an implementation.

**Language (open, Q4):** the `poop` repo has not yet declared one. The options considered are C11 (cheapest bootstrap, since stage0 already needs a C compiler; ADR-011) and Rust (memory-safe by default, but a much heavier bootstrap). The dependency list below assumes C and must be revised if Rust is chosen.

**Commands (v0):**

| Command | Purpose |
|---------|---------|
| `pkgmgr sync` | Fetch and verify the repository index |
| `pkgmgr install <pkg>...` | Install packages and their dependencies |
| `pkgmgr remove <pkg>...` | Remove packages that nothing else depends on, unless `--force` |
| `pkgmgr upgrade` | Upgrade all installed packages to the newest signed versions |
| `pkgmgr rollback <txid>` | Restore the file set from a previous transaction (archives kept in cache) |
| `pkgmgr verify` | Check installed files against the stored hashes |
| `pkgmgr build <recipe>` | Build one recipe in the sandbox and produce a package |
| `pkgmgr pack` / `pkgmgr repo-index` | Used by the repo tooling |

**Local database (assumed):** one SQLite file at `/var/lib/poopkg/db.sqlite`. Tables: `packages` (installed metadata), `files` (path → package, hash, mode), `transactions` (id, time, action, before/after), `pending` (crash-recovery journal). Every change is a single SQLite transaction. The database path is subject to Q1, the binary name.

**Transaction model:**

1. Resolve the requested change against the index. Produce an ordered plan, or fail with the conflict.
2. Download every package and verify its signature and hash. Nothing is installed if any check fails.
3. Extract into a staging directory under `/var/lib/poopkg/staging/<txid>/`.
4. Check every new path against the `files` table. A path owned by another package is a conflict and aborts the transaction.
5. Journal the plan in `pending`.
6. Move files into place, one package at a time, in dependency order. Keep the old files until the whole transaction commits.
7. Commit: update `packages` and `files`, record the transaction, delete `pending`.

If the power fails between steps 5 and 7, `pkgmgr` finishes or reverts the transaction on next start. Old package archives stay in `/var/cache/poopkg/` so `rollback` works without the network.

**Configuration files:** files under `/etc` that a user has changed are never overwritten silently. An upgrade writes the new version as `<file>.new` and reports it. There is no merge tool in v0.

**Dependency resolution:** a graph walk with version constraints (`>=`, `=`). Conflicts and cycles are errors. A full SAT solver is deferred to §7.

**Security properties:** signatures are checked before any file is written. Archives are extracted in a mode that refuses absolute paths, `..` components and device nodes outside an allow-list. Files are never executed during install. **Install scripts are not supported in v0**, which removes an entire class of privilege problems. If a package needs setup, it ships a config template or a poopsuite service definition instead.

### 3.2 Bootstrap chain

The bootstrap is the hardest part of a from-scratch distribution, and it is where most trust decisions live.

```
stage0  host toolchain from the archiso live environment (gcc, binutils, make, bash)
   │   checked against recorded hashes in bootstrap/stage0/
   ▼
stage1  temporary toolchain: binutils → gcc (pass 1, no libc)
   │      → linux-headers → musl-poop → gcc (pass 2, against musl-poop)
   │   installed into /opt/bootstrap, never into the final system
   ▼
stage2  base userland built with stage1: coreutils, bash, util-linux, findutils, sed, grep,
   │   gawk, tar, make, m4, bison, flex, ncurses, zlib, zstd, xz, libarchive, libcurl,
   │   sqlite, libsodium, openssl (or mbedtls), ca-certificates, dhcpcd, iwd, chrony, nftables
   │   and the kernel (linux-poop) with its initramfs generator
   ▼
stage3  poopsuite and pkgmgr built and installed into the stage2 root; package database initialised
   ▼
stage4  full self-hosting rebuild: every recipe rebuilt with pkgmgr inside the stage3 root
   │   output compared to the stage2 build for reproducibility (report, not hard-fail in v0)
   ▼
repo    signed packages and index, published to testing
```

**Trust statement:** in v0, stage0 trusts the archiso host toolchain. The seed is recorded by hash and documented, but it is not independently verified. Reducing this seed (stage0-posix, live-bootstrap style) is in §7.

**Ordering** lives in `bootstrap/order.txt`, one recipe per line. A recipe may depend only on lines above it, plus the stage0 host tools. CI rejects an order that violates this.

### 3.3 Sandbox and build isolation

- Builds run in a **chroot** on top of the current stage root, with a fresh `/proc`, `/dev` (minimal nodes), `/tmp` and `/var/tmp` mounts.
- Namespaces: a new mount, PID, IPC, UTS and user namespace where the host allows it. The network namespace is **off** for the build phase.
- Sources are fetched in a separate `fetch` phase, into a hash-addressed cache. The build phase has no network access. A build therefore cannot pull in an unverified input.
- The build environment is fixed: `LANG=C`, `TZ=UTC`, `umask 022`, `SOURCE_DATE_EPOCH` from the recipe's commit time, and a fixed set of `PATH` entries.
- Compiler hardening defaults for base recipes: `-fstack-protector-strong`, `-D_FORTIFY_SOURCE=3`, `-fPIE -pie`, `-Wl,-z,relro,-z,now`, `-Wformat -Werror=format-security`. musl-poop's own build flags are set by its recipe; performance flags must not weaken these defaults without an ADR.

### 3.4 Kernel pipeline

**Fork model (Proposed):**

- `poopware-laboratories/linux` `master` tracks upstream and carries Poop patches on top. Published `poop-v*` tags are never rebased.
- Upstream sync: merge each upstream stable point release within **14 days**, and within **72 hours** for a security fix that affects a shipped kernel.
- Keep the patch queue short. Every non-upstream patch needs a justification.

**Pinning (Accepted):** `kernel/source.env` holds the full commit SHA. The recipe fetches exactly that commit. Branch names are rejected by CI. The kernel is not vendored and not a submodule (ADR-007).

**Configuration:**

1. Start from `kernel/config/base.config`, an upstream-defconfig-derived file with the choices we want (no modules for the root filesystem, ext4 built in, EFI stub on, lockdown enabled).
2. Merge `kernel/config/fragments/*.config` on top with the kernel's `scripts/kconfig/merge_config.sh`.
3. Run `make olddefconfig` and fail CI if the result differs from the committed config.

**Artifacts:** `linux-poop` (kernel image, modules, EFI stub image) and `linux-poop-headers` (needed by musl-poop and by anything that builds against the kernel). Both come from the same build, so their versions cannot drift apart.

### 3.5 Initramfs

We do not use dracut or mkinitcpio, because both assume an ecosystem we do not ship.

- The generator builds a CPIO archive with a small **busybox** userland, the `init` script, and only the modules the image needs.
- `init` mounts `/proc`, `/sys`, `/dev`, finds the root partition by label (`POOP_ROOT`) or by a `root=` kernel argument, mounts it, and runs `switch_root` to the real PID 1 (`poopsuite`).
- Rescue: if the root mount fails, `init` drops to a busybox shell on the console and prints the reason.

### 3.6 Boot chain and Secure Boot

```
UEFI firmware ──▶ Limine (EFI binary) ──▶ signed kernel EFI image (linux-poop)
                                           + initramfs + command line in limine.conf
```

- **Limine** is the bootloader (Proposed, ADR-005). It is installed to the ESP by the installer. It supports multiple kernel entries, so the previous kernel stays bootable after an upgrade.
- **Kernel EFI image:** the kernel's EFI stub is used directly. Signing is done with `sbsigntools` (`sbsign`) for Secure Boot, using keys generated on the release machine.
- **Secure Boot** is supported with user-enrolled keys. We do not ship a Microsoft-signed shim in v0, which keeps the release process inside our own infrastructure (ADR-004).
- The command line is generated from `/etc/poop/cmdline`, not hard-coded in the image.

### 3.7 Init and services (poopsuite)

- **poopsuite** runs as PID 1 (ADR-002). Its repo describes it as a self-contained C boot stack with init, rc, a logger and user tools. This design relies on those parts. Their exact behaviour and service-definition format are defined by the `poopsuite` repo, and must be checked against it (Q10).
- Service definitions live in `init/services/<name>/`. They follow the format poopsuite defines. Enabling a service is poopsuite's job, not a symlink convention of ours.
- Base services: `agetty` on tty1–tty6, `dhcpcd`, `iwd` (Wi-Fi), `chronyd`, `nftables` (ruleset load at boot), and `sshd` if the `openssh` package is installed.
- Logging uses poopsuite's logger, with per-service logs in `/var/log/<service>/`. No journald.

### 3.8 Networking, DNS and time

| Concern | Choice | Notes |
|---------|--------|-------|
| Ethernet / DHCP | `dhcpcd` | Writes `/etc/resolv.conf`. Static config in `/etc/poop/network/` for servers. |
| Wi-Fi | `iwd` | Configured with `iwctl` on the TTY. |
| DNS | `resolv.conf` from `dhcpcd` | No resolver daemon in v0. |
| Time | `chrony` | Starts before login. The installer sets the initial clock. |
| Firewall | `nftables` via `poop-firewall` | Default deny inbound, allow established, allow loopback, allow ICMP echo. |

### 3.9 Filesystem layout

| Mount | Filesystem | Notes |
|-------|------------|-------|
| `/boot/efi` | FAT32 (ESP), 512 MiB | Limine, kernel EFI images. |
| `/` | ext4 | Single root in v0. |
| `/var/lib/poopkg` | (inside `/`) | Package database and staging. |
| `/var/cache/poopkg` | (inside `/`) | Package archives kept for rollback. |

No snapshots in v0. Rollback is done through `pkgmgr rollback` and by keeping previous kernels bootable. Filesystem snapshots are in §7.

### 3.10 Installer (TTY)

- A POSIX `sh` script with `dialog` for the UI. It is small enough to audit, and it runs in the live environment without extra runtime.
- Steps: pick disk (with a destructive-action confirmation), partition, create filesystems, set hostname and locale, create the user and root password, select optional packages (`openssh`), run `pkgmgr --root /mnt install`, configure the system, install Limine, reboot.
- The installer never runs untrusted code. It only calls `pkgmgr`, `sfdisk`, `mkfs.*`, and `chroot` into `/mnt`.

### 3.11 Live environment (archiso)

- `iso/` is a standard archiso profile. Its package list is the **bootstrap host set** only: enough to run `pkgmgr`, the installer and the network tools. It contains no distribution packages.
- The live image ships `pkgmgr`, the public keyring from `keyring/`, the installer, and the bootstrap host toolchain used for stage0.
- It autologs root into the installer on tty1. Other ttys give a shell.
- The archiso packages are not part of the installed system. The installer does not copy them.

### 3.12 Security baseline

- **Packages:** every package is signed. `pkgmgr` refuses unsigned packages. There is no "install anyway" flag in release configurations.
- **Privilege:** `doas` with the `wheel` group (ADR-012). Root login is locked by default.
- **Kernel:** lockdown in integrity mode, module signing enabled, `CONFIG_STRICT_DEVMEM`, hardened defaults in the fragments.
- **LSM:** no MAC policy in v0. Landlock and Yama are enabled in the kernel where a service opts in. AppArmor and SELinux are deferred (§7).
- **Network:** nftables default deny inbound. SSH is off unless installed and enabled.
- **Build:** sandbox with no network in build phase (§3.3). Hash-verified sources. Pinned component commits.

---

## 4. Scale and reliability

We are a static-artifact distributor and a bootstrap project, so the load is in build time and bandwidth, not in servers we run.

### 4.1 Load estimate (assumptions, to be replaced by real numbers)

| Quantity | Assumption | Result |
|----------|------------|--------|
| Full bootstrap | ~250 recipes | ~6 h on one 16-core runner |
| Live ISO size | ~700 MiB (bootstrap host tools + pkgmgr + installer + keyring) | ~17 TiB of egress at 25,000 downloads |
| Installed systems | 5,000 | — |
| Average daily update per system | ~5 MiB (text console, few services) | ~25 GiB / day package egress |
| Repo size per channel | ~1.5 GiB (all recipes in binary form) | Static, cacheable |
| Builds per week | ~40 (most rebuilds touch a single package) | One runner is enough at this stage |

**Conclusion:** the bootstrap is CPU-bound, so runners scale horizontally. Egress is the main hosting cost, and the design keeps artifacts immutable so a CDN can cache them.

### 4.2 Scaling strategy

- **Builds:** horizontal. Add runners. Source cache and binary cache are shared through object storage keyed by hash.
- **Distribution:** static files behind a CDN. Packages are immutable once published. The index changes often, so it gets a short TTL.
- **Bootstrap parallelism:** recipes with no edge between them build in parallel. The scheduler is `make -j` over generated targets.

### 4.3 Failover and redundancy

- The publish job writes to two origins. A failed origin does not block publishing.
- A bad release is rolled back by re-pointing `stable/` at the previous signed index. Old package files are kept for **90 days**.
- If CI is down, nothing ships, but every installed system keeps working and can still upgrade from `stable/`.

### 4.4 Monitoring and alerting

| Signal | Source | Alert |
|--------|--------|-------|
| Bootstrap failure on `main` | CI | Maintainers' channel, immediately |
| Reproducibility diff in stage4 | Rebuild job | Report in CI summary; becomes a gate later |
| Kernel upstream security release | Upstream stable feed | Triage within 24 h |
| musl-poop / poopsuite / poop upstream changes | Pinned repos | Review at each pin bump |
| `stable` freshness | Publish job | Warn at 14 days without a publish |
| Origin availability | External probe | Page after 3 failed probes |
| Boot and install test results | CI artifacts | Block promotion on failure |

### 4.5 Disaster recovery

- Everything needed to rebuild is in git, plus the pinned SHAs and the recorded seed hashes. Component repos are our own, so their history is also backed up by us.
- The offline master signing key has two custodians and an offline backup. A compromised signing subkey is revoked and replaced through `keyring/`.

---

## 5. Utility choices

Each choice has the reason we made it and the condition under which we would reconsider it. Status: **Accepted** unless marked *Proposed* or *Open*.

| Area | Choice | Alternatives considered | Why | Revisit when |
|------|--------|-------------------------|-----|--------------|
| **Distribution model** | From scratch: all packages built from source by our recipes | Arch packages as base; Debian packages as base; Buildroot | Matches the maintainers' plan. No dependency on another distro's package set in the target system. | Build cost exceeds the team's capacity. Then the seed or base set is revisited (§7). |
| **Package manager** | `pkgmgr`, in `poopware-laboratories/poop` | apk, pacman, dpkg/apt, xbps, Nix | Owned end to end; design fits the transaction and rollback goals (§3.1). | The team cannot keep up with maintenance. |
| **Package manager language** | **Open** (Q4). Options: C11 (*ADR-011*), Rust | Go; Python | Maintainers have not decided. C is the cheapest bootstrap; Rust is safer by default. | The `poop` repo declares a language; then this row is updated. |
| **Package format** | `.pkg.tar.zst` with `.pkginfo` and a detached Ed25519 signature | Custom binary format; `.deb`; `.apk` | tar + zstd is easy to inspect and to build; signatures are simple. | Need for delta updates or per-file dedup (§7). |
| **Signatures** | Ed25519, minisign-compatible, via libsodium | GPG; sigstore; TUF | Small verifier, no keyring daemon, easy to audit. | Need for supply-chain attestations (§7). |
| **Local database** | SQLite | Flat files (pacman-style); Berkeley DB | Transactions and queries built in; one file. | Database growth or performance issues. |
| **Repo transport** | Static HTTPS directory + signed index | rsync; OCI registry; IPFS | Static, cacheable, simple to mirror. | Needs for mirror discovery or push-based distribution. |
| **Recipe format** | `recipe.toml` metadata + `build.sh` | Lua; YAML; Python recipes | Declarative metadata that tools can read without running code; shell is the lingua franca for build steps. | Recipes need logic that shell cannot express cleanly. |
| **Build sandbox** | chroot + namespaces, no network in build phase | Containers (Docker); bubblewrap-only; VM per build | No daemon needed; the stage root is already a tree. | A build needs isolation that namespaces cannot give. |
| **Bootstrap seed (stage0)** | archiso live environment's host toolchain, hash-recorded | Full seed from source (stage0-posix); cross toolchain from another distro | Available immediately. Matches the chosen bootstrap path (archiso). | A reduced seed becomes a requirement (§7). |
| **C library** | **musl-poop**, our musl fork, focused on performance (ADR-013, Accepted) | glibc; upstream musl unchanged | Maintainers' decision. Small, clean, performance-focused. | Software we need requires glibc behaviour; then a compatibility layer is considered (§7). |
| **Init system / PID 1** | **poopsuite**, our C boot stack (ADR-002, Accepted) | runit; s6 / s6-rc; OpenRC; systemd | Maintainers' decision. Keeps the whole boot path in our control. | poopsuite cannot meet a requirement in F10 or §3.7. |
| **Core userland** | GNU coreutils, util-linux, findutils, sed, grep, gawk, tar, make, bash | BusyBox everywhere; toybox | Script compatibility and familiarity. BusyBox is used only in the initramfs and rescue shell. | Image size requirement becomes binding. |
| **Shell (login)** | bash | ksh/mksh, dash, fish | Default for scripts and users. | — |
| **Login / TTY** | agetty + login(1) on tty1–tty6, supervised by poopsuite | getty variants; greetd | Standard, small. | — |
| **Privilege escalation** | **doas** (ADR-012) | sudo; su only | Small, auditable, sufficient for a single-admin TTY system. | Users need fine-grained sudo policy. |
| **Bootloader** | **Limine** (*Proposed*, ADR-005) | GRUB; systemd-boot; syslinux | Small, UEFI and BIOS capable, multi-kernel entries, no systemd dependency. | Limine's Secure Boot story or maintenance changes. |
| **Kernel image signing** | kernel EFI stub, signed with `sbsigntools`, user-enrolled keys | UKI via ukify (needs systemd); shim | No systemd, no Microsoft signing. | Users need Secure Boot without enrolment (§7). |
| **Initramfs** | Own generator with busybox | dracut; mkinitcpio; initramfs-tools | Those depend on ecosystems we do not ship. | — |
| **Kernel** | Linux fork at `poopware-laboratories/linux`, pinned by SHA | Upstream unchanged; vendored tree | The fork is the product's kernel. Pinning keeps builds reproducible. | The fork needs its own release branch (§7). |
| **Kernel config** | Base config + merged fragments, drift-checked with `olddefconfig` | Full hand-edited `.config` | Fragments keep Poop changes reviewable. | The fragment count makes ordering matter. |
| **Filesystem** | ext4 for root, FAT32 for ESP | btrfs; XFS; ZFS | Simple and well understood in a from-scratch system. | Snapshots are needed (§7). |
| **Networking** | dhcpcd + iwd, static config for servers | NetworkManager (needs D-Bus); systemd-networkd | Small, TTY-friendly, no D-Bus stack. | Need a richer network manager for a laptop edition. |
| **Time** | chrony | ntpd; openntpd; systemd-timesyncd | Accurate, small, well maintained. | — |
| **Firewall** | nftables with a shipped ruleset | iptables; firewalld | Kernel-native, declarative, one tool. | — |
| **Installer** | POSIX sh + dialog | Python TUI; a Rust/C installer; archinstall | Auditable, no runtime beyond the live environment's shell and dialog. | Installer logic becomes too complex for shell. |
| **Live environment** | archiso profile with a bootstrap-host package set | Custom live builder; Buildroot | archiso is the chosen bootstrap path. Only the live image uses it. | archiso stops working on our CI runner. |
| **Desktop** | **None in v0** (TTY-only) | Plasma; GNOME; Sway | Maintainers' decision. | Desktop edition is planned (§7). |
| **Containers** | None in v0 | Podman; Docker | Out of scope for a TTY base. | Users need containers in the base (§7). |
| **Editions** | One: `tty` | minimal + desktop | Maintainers' decision. | — |
| **CI** | GitHub Actions for lint and unit tests; **self-hosted runner** for bootstrap, kernel and ISO | Hosted only; Buildbot | Bootstrap needs root, large disk and long jobs. | Build volume outgrows one runner. |
| **Build orchestration** | `make` + bash scripts (`shellcheck`-clean) | `just`; Python; Bazel | Available everywhere. Bootstrap order is a plain file. | Target count becomes hard to read. |
| **Testing** | `pkgmgr` unit tests in the `poop` repo; scenario tests in a stage root here; QEMU+OVMF boot and install tests | Manual testing only | Automatable and repeatable. | Hardware-in-the-loop tests (§7). |
| **Hosting** | Object storage origin behind a CDN (*Proposed*, ADR-010) | GitHub Releases; self-hosted server | Egress-heavy workload is cheap there. The maintainers' answer did not cover hosting; see §8 Q5. | Egress costs or provider limits change. |
| **Commit / PR conventions** | Conventional Commits; PR template | Free-form | Machine-readable changelog. | — |
| **Licensing** | Our code, recipes and docs under **EUPL-1.2** (ADR-014, Accepted) | MIT; GPL-2.0 for everything | Maintainers' decision. EUPL-1.2 lists GPL-2.0 as compatible, so it fits with the GPL kernel. | Legal review finds an incompatibility. |
| **Branding** | Own name, logo and text in `branding/`. No third-party marks. | Keeping upstream branding | Avoids trademark confusion. | — |

---

## 6. Trade-off analysis and decision log

Each decision below is an ADR. The full record goes in `docs/decisions/NNNN-<title>.md` when accepted. Trade-offs are listed here so the reasoning is in one place.

### ADR-001 — From-scratch base with our own recipes (Accepted, maintainer decision)

- **Options:** from-scratch; Arch packages as base; Debian packages as base; Buildroot.
- **Chosen:** from scratch. Every package is built from upstream source by our recipes or pinned to our own repos.
- **Gains:** full control of the system, no dependency on another distro's package set, a coherent design for the package manager.
- **Costs:** the bootstrap is large. Security updates for everything we ship fall on us. Time to a usable system is the longest of all options.

### ADR-002 — poopsuite as PID 1 and supervisor (Accepted, maintainer decision)

- **Gains:** the whole boot path, from PID 1 to the logger, is one project under our control.
- **Costs:** we carry the bugs and the security work for init. Its service-definition format and feature set must be verified against the `poopsuite` repo before the base services in §3.7 are written (Q10). Tools that expect systemd or runit service formats need adapters.

### ADR-003 — Package manager is ours, in its own repo (Accepted, maintainer decision)

- **Gains:** design fits our transaction and rollback goals. The repo pin here keeps the integrated system reproducible.
- **Costs:** we own all the bugs. The `poop` repo needs its own unit and fuzz tests, and this repo needs scenario tests from day one.

### ADR-004 — No Microsoft-signed shim in v0 (*Proposed*)

- **Gains:** release process stays inside our infrastructure.
- **Costs:** Secure Boot requires key enrolment, which will confuse some users. Documented in the installer.

### ADR-005 — Limine as bootloader (*Proposed*)

- **Gains:** small, UEFI and BIOS capable, multi-kernel entries, no systemd dependency.
- **Costs:** a smaller user base and less documentation than GRUB. We carry the config and any Secure Boot glue ourselves.

### ADR-006 — TTY-only in v0 (Accepted, maintainer decision)

- **Gains:** a much smaller scope. No display stack, no audio, no desktop defaults to maintain.
- **Costs:** a large group of potential users are out of reach until a desktop edition is planned.

### ADR-007 — Pin the kernel by SHA, no submodule, no vendoring (Accepted)

- **Gains:** reproducible builds, no 5 GiB tree in our repo, explicit upgrade commits.
- **Costs:** the bump is a manual step in `kernel/source.env`. CI builds the bump on every PR that touches it.

### ADR-008 — One edition: `tty` (Accepted, follows ADR-006)

- **Gains:** one image to build, test and document.
- **Costs:** server and desktop users both have to add what they need through packages.

### ADR-009 — Self-hosted runner for bootstrap and image builds (Accepted)

- **Gains:** bootstrap and `mkarchiso` need root, large disk and long jobs.
- **Costs:** one machine is a single point of failure for releases. Mitigation: a second runner (§4.2).

### ADR-010 — Object storage origin behind a CDN for artifacts (*Proposed*)

- **Gains:** egress-heavy traffic is cheap, cacheable, and needs no servers.
- **Costs:** a vendor dependency, and an egress bill to watch. Two origins for failover (§4.3).

### ADR-011 — Language for `pkgmgr` (**Open**, Q4)

- **Options:** C11 (cheapest bootstrap, manual memory safety; mitigated by fuzzing and sanitizers) or Rust (memory-safe by default; large bootstrap).
- **Status:** not decided. The `poop` repo will record the decision in its own ADR, and this repo will update §5 when it does.

### ADR-012 — doas for privilege escalation (Accepted)

- **Gains:** small, auditable, fits a single-admin system.
- **Costs:** less policy depth than sudo. Users who need fine-grained rules will have to ask for them.

### ADR-013 — musl-poop as C library (Accepted, maintainer decision)

- **Gains:** a small, clean libc we control, with a performance focus that matches our goals.
- **Costs:** third-party software that depends on glibc behaviour is not supported in the base. We maintain a downstream fork, so upstream musl changes must be reviewed and merged on our schedule. Performance claims about musl-poop require benchmarks (`AGENTS.md` §4.5).

### ADR-014 — EUPL-1.2 for project code (Accepted, maintainer decision)

- **Options:** EUPL-1.2; MIT; GPL-2.0 for everything.
- **Chosen:** EUPL-1.2 in `LICENSE` for our code, recipes and documentation.
- **Gains:** a licence with an EU legal basis and an appendix of compatible licences, including GPL-2.0, so the GPL-2.0-only kernel and our code can be combined.
- **Costs:** fewer contributors and downstream projects are familiar with EUPL than with MIT or GPL. Every new source file needs the SPDX header (CONTRIBUTING §17).

---

## 7. Revisit as the system grows

| Topic | Trigger | Likely direction |
|-------|---------|------------------|
| Bootstrap seed | Trust review requires an independent seed | stage0-posix or live-bootstrap style seed |
| glibc compatibility | Required third-party software needs glibc | Compatibility layer, or a glibc-based variant, through a new ADR |
| musl-poop upstream sync | Upstream musl releases security or correctness fixes | Sync policy in the musl-poop repo, mirrored in a pin-bump checklist here |
| Desktop edition | Maintainers plan a graphical edition | Add `desktop` edition: Wayland compositor, audio, a chosen DE (new ADR) |
| Containers | Users need containers in the base | Add Podman or a lighter runtime as an optional package |
| Package manager solver | Dependency graphs grow beyond simple walks | SAT-based solver, or a PubGrub-style resolver |
| Snapshots and boot-menu rollback | Users roll back bad upgrades often | btrfs or ZFS root, snapshot entries in Limine |
| MAC policy | Need for stronger isolation of services | AppArmor or Landlock-based policies for our services |
| Secure Boot UX | Enrolment becomes a support burden | Shim signing process, or guided enrolment in the installer |
| Supply-chain hardening | Repo grows or user base grows | TUF or sigstore attestations; reproducibility as a hard gate |
| Architectures | Demand for aarch64 or RISC-V | New bootstrap stage per architecture; cross toolchain in stage1 |
| Init changes | poopsuite cannot meet a requirement | Replace poopsuite only through an ADR and a migration plan |
| Kernel patch volume | Fork carries many non-upstream patches | Dedicated release branches and a patch-queue tool |
| Legacy BIOS | Target users need it | Limine BIOS path in the installer |
| Hosting | Egress bill grows, or the provider changes terms | Move origin, add a mirror network, or add torrent seeding |
| CI capacity | Bootstrap queues for hours | More runners; split kernel builds onto their own runner |
| Team size | More than ~6 maintainers | CODEOWNERS per directory and formal review rules |

---

## 8. Open questions

These need maintainer decisions. Each blocks a specific milestone (§9).

- **Q1 — Binary name of the package manager.** The repo is `poop`, and the design uses `pkgmgr` as a working name. Confirm the binary name, the database path (`/var/lib/poopkg`) and the cache path before the first package is published, because they appear in the ISO, the database path and the docs.
- **Q4 — Package manager language:** C11 (ADR-011) or Rust, accepting a heavier bootstrap. This is the open decision in the `poop` repo.
- **Q5 — Hosting:** the answer "bootstrap into a system, user uses archiso to bootstrap the distro" was read as describing the install path, not repo hosting. Repo hosting is still open. Object storage + CDN (ADR-010), or another origin.
- **Q6 — Bootloader:** Limine (ADR-005) or GRUB for a larger support base.
- **Q7 — Signing custody:** who holds the offline master key, and how many custodians are needed to sign a keyring change.
- **Q8 — Name and trademark:** confirm "Poop Linux" and its branding are cleared for public use before the first public ISO.
- **Q9 — Kernel features for v1:** which fragments and patches go in (hardening, scheduler changes, LTO). Needs a benchmark plan first.
- **Q10 — poopsuite fit:** check the `poopsuite` repo for service-definition format, supervision semantics (restart policy, dependency ordering), logger behaviour and user tools. §3.7 and the base services depend on the answer.
- **Q11 — musl-poop scope:** which performance changes go in, how they are benchmarked (§4.5 of `AGENTS.md`), and how upstream musl changes are synced.

---

## 9. Milestones

| Phase | Deliverable | Exit criteria |
|-------|-------------|---------------|
| 0 — Foundations | Repo skeleton, `Makefile`, lint CI, this design, `.gitignore`, `bootstrap/order.txt` (empty) | `make lint` passes on `main`; CI green |
| 1 — pkgmgr MVP (in the `poop` repo) | `pkgmgr` with `sync`, `install`, `remove`, signature checks, SQLite database, one-transaction commit. Language decided (Q4). | Scenario tests pass in a throwaway stage root; fuzzed archive parser has no crashes in a 1-hour run |
| 2 — Stage0 and stage1 | `bootstrap/stage1` builds binutils, gcc (pass 1 and 2), linux headers, musl-poop | Stage1 toolchain compiles and runs a hello-world with `-fstack-protector-strong`, linked against musl-poop |
| 3 — Stage2 base | Base userland (§3.2 stage2), `linux-poop` with the initramfs generator, poopsuite as PID 1 (Q10 closed) | Base builds in the sandbox; kernel boots to a busybox shell and poopsuite starts a service in QEMU |
| 4 — Self-hosting | `pkgmgr` builds itself; full stage4 rebuild; reproducibility report | Stage4 completes; reproducibility report published in CI |
| 5 — Installer and live ISO | `iso/` archiso profile, TTY installer, Limine, signed kernel | ISO boots in QEMU/OVMF; installer completes; installed system boots to login |
| 6 — Release | `stable` channel, origins, changelog, first public `tty` ISO | §4.3 and §4.4 wired up; Q5, Q7, Q8 closed |

---

## 10. Glossary

- **Stage0 / stage1 / stage2:** bootstrap levels. Stage0 is the host toolchain. Stage1 is a temporary toolchain. Stage2 is the base built with stage1.
- **Recipe:** the build description for one package (`recipe.toml` and `build.sh`).
- **pkgmgr:** our package manager (working name, Q1), developed in `poopware-laboratories/poop`.
- **poopsuite:** our C boot stack, used as PID 1 and supervisor.
- **musl-poop:** our downstream fork of musl, used as the C library.
- **Transaction:** one install, remove or upgrade run. It commits or rolls back as a unit.
- **archiso:** Arch's tool for building live ISOs. Used here only for the live bootstrap environment.
- **UEFI stub:** the EFI-loadable entry in the Linux kernel image, which lets the firmware boot the kernel directly.
- **Pinned SHA:** a full git commit hash used as the source for a build, so the input can never change under us.
