# Poop Linux — Architecture

Status: **Draft v0.1** (2026-11-02). Decisions marked *Accepted* are binding for v0.x; *Proposed* ones need maintainer sign-off before the milestone that depends on them.

This document is the system design for the Poop Linux distribution and for this repository. It answers four questions: what we build, how the pieces fit, which utilities we chose and why, and what we will revisit as the project grows. Process rules live in [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`AGENTS.md`](AGENTS.md); this file is the reference for *why the repo looks the way it does*.

---

## 0. Summary

Poop Linux is an x86_64 Linux distribution whose kernel is built from our fork, [`poopware-laboratories/linux`](https://github.com/poopware-laboratories/linux) (a fork of `torvalds/linux`). Everything above the kernel is packaged in the **Arch Linux packaging model** (PKGBUILD, `makepkg`, `pacman`), images are built with **archiso**, and we publish our own signed package repositories that sit beside, and selectively override, upstream Arch packages.

We chose the Arch model because it gives us a maintained package ecosystem, a rolling-release update path, and a small set of build tools, while keeping the distribution-specific surface (kernel, branding, defaults, installer config) small enough for a few part-time maintainers to own.

Key facts at the time of writing:

- The kernel fork is **currently identical to upstream** (`0 ahead / 0 behind` `torvalds/linux` master, head `Linux 7.4-rc1`). There are no Poop-specific kernel patches yet, so v0 ships an upstream kernel built from our fork's pinned commit. Kernel customisation is a later milestone.
- `origin` is `git@github.com:poopware-laboratories/pooplinux.git`. `main` had no commits when this design was written.

---

## 1. Requirements

### 1.1 Functional requirements

| ID | Requirement |
|----|-------------|
| F1 | Build a bootable x86_64 ISO for two editions: **minimal** (CLI) and **desktop** (graphical). |
| F2 | Build the kernel (`linux-poop`) from a **pinned commit** of `poopware-laboratories/linux`. Builds must not float on a moving branch. |
| F3 | Build every distribution-specific package (`poop-*`, `linux-poop*`) from source in this repo, and publish them as **signed** pacman repositories. |
| F4 | Install to disk on UEFI firmware, with ext4 (minimal) or btrfs (desktop). |
| F5 | Upgrade installed systems with `pacman -Syu` against our repositories. |
| F6 | Keep the previous kernel bootable after any kernel upgrade. |
| F7 | Provide branding and default settings as packages, so derivatives can swap them out. |
| F8 | Allow any contributor to reproduce a release artifact from the repo plus the pinned inputs. |

### 1.2 Non-functional requirements

These are **proposed targets**. Each one gets measured in CI before we claim it.

| Area | Target | Measured by |
|------|--------|-------------|
| Kernel build time | < 45 min on a 16-core runner with warm ccache | CI job timing |
| ISO build time | < 60 min end-to-end on the CI runner | CI job timing |
| Boot to login prompt (QEMU, OVMF, 2 vCPU, 4 GiB) | < 30 s | Boot smoke test |
| Critical kernel CVE → shipped fix | < 72 h after upstream fix lands | Release log |
| Package repo availability | 99.9 % per month | CDN uptime probe |
| ISO size | minimal < 1.2 GiB, desktop < 3.5 GiB | Build output |
| Reproducibility | Same inputs → same package file hashes, modulo documented exceptions | `SOURCE_DATE_EPOCH` + rebuild check |
| Licensing | Every shipped component redistributable. Non-free firmware is opt-in. | Package license audit |

### 1.3 Constraints and assumptions

- **Team (assumed):** 2–4 part-time maintainers. Anything that needs a dedicated ops person is out of scope for v0.
- **Timeline (assumed):** MVP (minimal ISO that boots in QEMU and installs) in about six weeks. The desktop edition follows.
- **Existing stack:** the kernel fork (GPL-2.0), a GitHub organisation, and an existing `pooplinux` repo with no history.
- **No forking of the whole Arch archive.** We reuse upstream Arch packages wherever they are acceptable and override only what we must.
- **Hardware scope v0:** x86_64, UEFI only. aarch64 and legacy BIOS are deferred (see §7).

---

## 2. High-level design

### 2.1 Component diagram

```
                       ┌────────────────────────────────────┐
  torvalds/linux ─────▶│ poopware-laboratories/linux        │  kernel fork
  (upstream tags)      │ master = upstream + poop patches   │  (pinned by SHA)
                       └─────────────────┬──────────────────┘
                                         │ git fetch @ pinned commit
┌──────────────────────┐                 ▼
│ Arch upstream repos  │      ┌────────────────────────────────┐
│ core / extra         │─────▶│ packages/   PKGBUILDs          │
│ (reused, not forked) │      │   kernel/   linux-poop         │
└──────────────────────┘      │   poop-*    our packages       │
                              └───────────────┬────────────────┘
                                              │ makepkg + repo-add -s   (CI)
                              ┌───────────────▼────────────────┐
                              │ Signed repos                   │
                              │   poop-testing → poop-stable   │──────┐
                              └───────────────┬────────────────┘      │ pacman -Syu
                                              │                       ▼
                              ┌───────────────▼────────────────┐  installed systems
                              │ profiles/   archiso profiles   │
                              │   minimal/  desktop/           │
                              └───────────────┬────────────────┘
                                              │ mkarchiso           (CI, privileged)
                              ┌───────────────▼────────────────┐
                              │ ISO image  poop-<ed>-<date>.iso│
                              └───────────────┬────────────────┘
                                              │ QEMU+OVMF boot test (gate)
                                              ▼
                                     CDN release artifacts
```

### 2.2 Software stack (what runs on an installed system)

```
  ┌──────────────────────────────────────────────────────────────┐
  │ Apps          Flatpak (Flathub) · Podman containers          │
  ├──────────────────────────────────────────────────────────────┤
  │ Desktop       KDE Plasma 6 on Wayland (desktop edition)      │  ← Proposed
  │               none (minimal edition)                         │
  ├──────────────────────────────────────────────────────────────┤
  │ Services      NetworkManager · systemd-resolved · timesyncd  │
  │               nftables (poop-firewall) · PipeWire · AppArmor│
  ├──────────────────────────────────────────────────────────────┤
  │ Userspace     systemd (PID 1) · glibc · GNU coreutils        │
  │               util-linux · bash · pacman · sudo              │
  ├──────────────────────────────────────────────────────────────┤
  │ Kernel        linux-poop (from poopware-laboratories/linux)  │
  │               + initramfs built by mkinitcpio                │
  ├──────────────────────────────────────────────────────────────┤
  │ Boot          systemd-boot → signed Unified Kernel Image     │
  │ Firmware      UEFI + Secure Boot (user-enrolled keys, sbctl) │
  └──────────────────────────────────────────────────────────────┘
```

### 2.3 Data flows

**Build flow (per release):**

```
kernel/source.env ──▶ fetch fork @ SHA ──▶ merge config fragments ──▶ makepkg linux-poop
                                                                          │
packages/poop-*/PKGBUILD ──▶ makepkg (namcap, checksums) ──────────────────┤
                                                                          ▼
                                             repo-add -s  ──▶ poop-testing repo
                                                                          │
                              smoke install + boot test (QEMU) ◀──────────┤
                                                                          ▼ promote
profiles/<ed>/ ──▶ mkarchiso (uses poop-stable) ──▶ ISO ──▶ boot gate ──▶ release
```

**Update flow (installed system):**

```
pacman -Syu ──▶ pre-transaction snapshot (desktop, btrfs/snapper via snap-pac)
           ──▶ download from poop-stable (signature-verified)
           ──▶ install; mkinitcpio + ukify regenerate UKI and sign it (sbctl)
           ──▶ systemd-boot entry for new kernel; previous kernel entry retained
```

**Install flow:**

```
ISO boot (UEFI) ──▶ installer (Calamares desktop / archinstall minimal)
  ──▶ partition (ESP + root)  ──▶ pacstrap with poop-stable pacman.conf
  ──▶ configure users, locale, network  ──▶ bootctl install + UKI  ──▶ reboot
```

### 2.4 Contracts

These are the interfaces other parts of the repo and external consumers depend on. Changing one needs an ADR (§6) and a CHANGELOG entry.

**Repository layout (target):**

```
pooplinux/
├── README.md                 entry point for humans
├── ARCHITECTURE.md           this document
├── AGENTS.md                 instructions for AI coding agents (canonical)
├── CLAUDE.md                 Claude Code entry point; imports AGENTS.md
├── CONTRIBUTING.md           contributor workflow
├── CHANGELOG.md              release notes (Keep a Changelog format)
├── Makefile                  the only supported entry point for builds
├── .gitignore
├── kernel/
│   ├── source.env            POOP_KERNEL_REPO, POOP_KERNEL_SHA, POOP_KERNEL_VERSION
│   ├── PKGBUILD              linux-poop (+ -headers)
│   ├── config/
│   │   ├── base.config       starting kernel config (Arch-style, from upstream defconfig)
│   │   └── fragments/*.config  Poop-specific options, merged on top of base
│   └── patches/              reserved; empty until the fork carries non-upstream patches
├── packages/
│   ├── poop-branding/        logos, os-release, GRUB/Plymouth/SDDM themes
│   ├── poop-settings/        default config in /usr/share/factory and /etc/skel
│   ├── poop-base/            meta-package: minimal system set
│   ├── poop-desktop/         meta-package: Plasma + desktop defaults
│   ├── poop-firewall/        nftables ruleset, default deny inbound
│   └── poop-keyring/         distro keyring and repo signing public key
├── repo/
│   ├── pacman.conf           repo definitions for CI and end users
│   └── channels.md           testing → stable promotion rules
├── profiles/
│   ├── minimal/              archiso profile (profiledef.sh, packages.x86_64, airootfs/)
│   └── desktop/              archiso profile + Calamares config
├── installer/
│   └── calamares/            Calamares modules and branding
├── scripts/                  build helpers (bash, shellcheck-clean)
├── tests/
│   ├── lint/                 PKGBUILD / shell / config checks
│   └── boot/                 QEMU+OVMF smoke tests
├── docs/
│   └── decisions/            ADRs (NNNN-title.md)
└── .github/workflows/        CI definitions
```

**Package naming and versioning:**

- Distribution packages use the `poop-` prefix. Kernel packages are `linux-poop` and `linux-poop-headers`.
- `pkgver` for the kernel mirrors the upstream version (`7.4.rc1` style is converted to `7.4rc1`, following Arch's convention). The Poop revision goes in `pkgrel`.
- Tags in the kernel fork follow `poop-v<kver>-<n>`, with `<n>` the Poop patch-set revision.
- ISO names: `poop-<edition>-<YYYY.MM.DD>-x86_64.iso`.

**Pinned inputs (`kernel/source.env`):**

```bash
POOP_KERNEL_REPO="https://github.com/poopware-laboratories/linux.git"
POOP_KERNEL_SHA="6628e7d4c6b25c8d18f1345e3a20d21829aae7e4"   # Linux 7.4-rc1 at time of writing
POOP_KERNEL_VERSION="7.4rc1"
```

The PKGBUILD consumes this file. Bumping the kernel is a one-line change that CI validates (§3.1).

**Profile contract:** each `profiles/<name>/` is a valid archiso profile. Its `packages.x86_64` may reference only packages from upstream Arch repos or from `poop-*` repos, and every `poop-*` package must exist in `poop-testing` or `poop-stable`.

**Repository channels:**

| Channel | Purpose | Who consumes it | Promotion gate |
|---------|---------|-----------------|----------------|
| `poop-testing` | Every successful CI build | Maintainers, early adopters | Automatic on green CI |
| `poop-stable` | Default for installs and updates | Everyone | Boot test + one week in testing (kernel), or manual sign-off (other packages) |

---

## 3. Deep dive

### 3.1 Kernel pipeline

**Fork model (Proposed):**

- `poopware-laboratories/linux` `master` tracks upstream and carries Poop patches on top. We do not rebase published `poop-v*` tags.
- Upstream sync: merge each upstream stable point release within **14 days**, and within **72 hours** for a security fix that affects a shipped kernel.
- Keep the patch queue short. Every non-upstream patch needs a line in `docs/decisions/` or a comment in the commit that says why it is not upstream.

**Pinning (Accepted):** the PKGBUILD fetches the fork by **full commit SHA** (`source=("git+${POOP_KERNEL_REPO}#commit=${POOP_KERNEL_SHA}")`). We do not use a branch name, and we do not vendor the kernel tree into this repo. Vendoring would make this repo about 5 GiB and would hide kernel history. A git submodule would couple every clone to the kernel tree for no gain.

**Configuration:**

1. Start from `kernel/config/base.config`, which is an Arch-style config seeded from upstream `defconfig` plus our distro choices (AppArmor, no `CONFIG_MODULES` drop for v0).
2. Merge `kernel/config/fragments/*.config` on top with the kernel's own `scripts/kconfig/merge_config.sh`.
3. Run `make olddefconfig` and fail CI if the result differs from the committed config, so drift is always explicit.

**Build flags:** LTO and any scheduler changes are **not** enabled in v0. They are candidates for a later fragment once the fork carries the relevant patches and we have benchmarks (see the benchmark rule in `AGENTS.md`).

**Kernel artifacts:** `linux-poop` (kernel image and modules), `linux-poop-headers`. Both are split packages built from the same source, and the modules are tied to the `pkgver` of the kernel that built them.

### 3.2 Package model

- Every package is a PKGBUILD, built with `makepkg` in a clean chroot (`extra-x86_64-build` or equivalent) so we never depend on the host.
- Sources must have **checksums**. `SKIP` is allowed only for git sources pinned by commit SHA.
- `namcap` runs on every package. Failures block merge.
- Repos are built with `repo-add -s`. Packages and the database are both signed.
- `SigLevel = Required DatabaseOptional` in every `pacman.conf` we ship, so unsigned packages are rejected.
- Signing key custody: the **master key is offline** (on hardware tokens, with a backup held by a second maintainer). CI signs with a dedicated **signing subkey** stored in CI secrets. Rotation procedure is in `CONTRIBUTING.md`.

### 3.3 Image build

- `mkarchiso` builds both editions from `profiles/`. It needs root and loop devices, so CI runs it in a **privileged container on a self-hosted Arch runner**. Hosted runners are not enough for this.
- `SOURCE_DATE_EPOCH` is set from the git commit time, so file timestamps in the ISO match the source.
- The ISO build fails if any package in `packages.x86_64` is missing from both upstream and `poop-stable`.

### 3.4 Boot chain and Secure Boot

```
UEFI firmware ──▶ systemd-boot (signed) ──▶ Unified Kernel Image (UKI, signed)
                                             = linux-poop + initramfs + cmdline
```

- **systemd-boot** is the bootloader. It is installed with `bootctl`.
- **UKI** images are built with `mkinitcpio` and `systemd-ukify`, so the kernel, initramfs and command line are one signed file. This closes the gap where a modified initramfs could be swapped in on an unsigned ESP.
- **Secure Boot** is supported with **user-enrolled keys** through `sbctl`. We do not ship a Microsoft-signed `shim` in v0, because that requires a Microsoft signing process. Secure Boot is therefore optional: the installer explains how to enable it, but does not turn it on.
- Previous kernel UKIs are kept, so a broken kernel can be booted from the menu.

### 3.5 Filesystem layout and snapshots

| Edition | Root FS | Subvolumes / notes |
|---------|---------|--------------------|
| minimal | ext4 | Single root, separate ESP at `/boot` (vfat). |
| desktop | btrfs | `@` (root), `@home`, `@snapshots`, `@var_log`, `@var_cache`. `snapper` for root; `snap-pac` snapshots before and after each pacman transaction. |

**Known limitation:** systemd-boot does not list snapshots as boot entries, so rolling back to a snapshot is a manual step (`snapper rollback` from a live ISO or a recovery shell). We accept this in v0 and revisit it in §7.

### 3.6 Installer

- **Desktop edition:** Calamares, with our modules and branding in `installer/calamares/`. Its `pacstrap` step is pointed at a `pacman.conf` that uses `poop-stable`.
- **Minimal edition:** `archinstall`, with a bundled config that sets the `poop-stable` repo and `poop-base`. We do not fork `archinstall`; we configure it.
- Both installers use the same partitioning defaults (§3.5) and the same bootloader setup (§3.4).

### 3.7 Security baseline

- **LSM:** AppArmor, enabled on the kernel command line (`lsm=landlock,lockdown,yama,apparmor,bpf`). No SELinux in v0.
- **Firewall:** `poop-firewall` ships an nftables ruleset with **default deny inbound** and default allow outbound. It is enabled by default on both editions.
- **Privilege:** `sudo` with the `wheel` group. No root password login by default.
- **Containers:** rootless **Podman**. The Docker daemon is not shipped.
- **Packages:** signature checks on everything (§3.2).
- **Hardening:** systemd unit sandboxing is applied to the services we own. Upstream services keep their defaults.
- **Vulnerability tracking:** the kernel fork is watched for upstream security fixes (§3.1), and our advisories are published in `CHANGELOG.md`.

### 3.8 Error handling and retries

| Failure | Behaviour |
|---------|-----------|
| Source download fails (network) | CI retries 3 times with backoff, then fails the job. No partial artifacts. |
| Checksum mismatch | Hard fail. Never auto-update checksums. |
| `namcap` or `shellcheck` error | Hard fail, blocks merge. |
| `olddefconfig` drift in kernel config | Hard fail. The fix is to commit the regenerated config deliberately. |
| Boot smoke test fails | Artifact is not promoted. The previous `poop-stable` stays live. |
| Signing step fails | Nothing is published. CI never falls back to an unsigned repo. |
| Package in profile is missing from repos | ISO build fails. Never ship a half-populated image. |

---

## 4. Scale and reliability

We are a static-artifact distributor, so the load is in bandwidth and build time, not in servers we run.

### 4.1 Load estimate (assumptions, to be replaced by real numbers)

| Quantity | Assumption | Result |
|----------|------------|--------|
| ISO downloads per month | 10,000 at 2.5 GiB | ~25 TiB / month of ISO egress |
| Installed systems | 5,000 | — |
| Average daily update per system | ~50 MiB | ~250 GiB / day, ~7.5 TiB / month of package egress |
| Packages per release (kernel + poop-* + profile-specific) | ~200 files | Repo size ~ 1–2 GiB per channel |
| CI builds per week | ~40 (kernel is the expensive one) | ~1 kernel build per day on the self-hosted runner |

**Conclusion:** egress dominates cost, not compute. Hosting must sit behind a CDN, and ISO downloads should also be offered as a torrent or mirror list. A single runner handles the build load at this scale. More runners can be added without changing the design.

### 4.2 Scaling strategy

- **Builds:** horizontal. Add runners. Kernel ccache is shared through a cache bucket.
- **Distribution:** CDN in front of an object-storage origin (see ADR-010). Packages are immutable once published, which makes caching trivial.
- **Metadata:** `poop-stable` and `poop-testing` databases are small and change often, so they get short cache TTLs. Package files get long TTLs.

### 4.3 Failover and redundancy

- Repos are mirrored to **two origins** in different regions by the publish job. A failed origin does not block publishing.
- A bad release can be rolled back by repointing `poop-stable` to the previous snapshot. We keep **90 days** of published package versions and every ISO.
- If CI is down, nothing ships. Users keep getting updates from `poop-stable`, which is already built and signed.

### 4.4 Monitoring and alerting

| Signal | Source | Alert |
|--------|--------|-------|
| CI failures on `main` | GitHub Actions | Maintainers' channel, immediately |
| Kernel upstream security release | Upstream stable feed | Triage within 24 h |
| `poop-stable` freshness (last publish age) | Publish job | Warn at 7 days without a publish |
| CDN availability | External probe | Page after 3 failed probes |
| Boot test results | CI artifacts | Block promotion on failure |

### 4.5 Disaster recovery

- Everything needed to rebuild is in git, plus the pinned kernel SHA. Losing the CI runner loses time, not data.
- The offline master signing key has two custodians and an offline backup. Loss of the subkey is handled by revoking it and publishing a new one through the keyring package (`poop-keyring`).

---

## 5. Utility choices

This is the catalogue of tools and their roles. Each choice has the reason we made it and the condition under which we would reconsider it. Status: **Accepted** unless noted.

| Area | Choice | Alternatives considered | Why | Revisit when |
|------|--------|--------------------------|-----|--------------|
| **Base packaging model** | Arch Linux PKGBUILD / `makepkg` / `pacman` | Buildroot, Debian `live-build` + `.deb`, Nix/NixOS, Yocto | Mature ecosystem, rolling updates, simple recipe format, one tool for builds and installs. Buildroot is great for appliances but has no installed-system update story. Nix changes the whole mental model. | Our repo needs more than ~200 distro-owned packages, or a different base is required for a target device. |
| **Upstream package source** | Reuse upstream Arch `core`/`extra`/`multilib` where acceptable; override with `poop-*` only where needed | Fork all of Arch; build everything ourselves | Forking the archive is unaffordable for a small team. Overrides are small and explicit. | Upstream stops shipping something we depend on, or licensing/policy diverges. |
| **Kernel** | `linux-poop` built from `poopware-laboratories/linux`, pinned by SHA | Use upstream `linux` package unchanged; vendor the tree | The fork is the product's kernel. Pinning keeps builds reproducible. | The fork carries enough patches that we need a dedicated release branch. |
| **Kernel config** | Arch-style base config + merged fragments, checked by `olddefconfig` | Hand-maintained full `.config`; `make menuconfig` in CI | Fragments make Poop changes reviewable as small diffs. | The number of fragments makes ordering matter. |
| **ISO builder** | `archiso` (`mkarchiso`) | Cubic (GUI), Kiwi, live-build | Same tool family as the package model. Profiles are plain files. | archiso is unmaintained, or we need non-x86 images. |
| **Init system** | **systemd** | runit, s6, OpenRC | Default for the Arch model, widest unit ecosystem, all the services we want to ship (`resolved`, `timesyncd`, `ukify`, `homed` options) have first-class units. | Maintainers want a non-systemd edition. Consider as a separate variant rather than a replacement. |
| **Bootloader** | **systemd-boot** on UEFI | GRUB, rEFInd, Limine | Simple, small, works with UKIs and Secure Boot via `sbctl`. | We need BIOS/legacy support, or a boot menu feature that systemd-boot lacks. |
| **Boot image format** | **Unified Kernel Image** via `mkinitcpio` + `systemd-ukify` | Separate kernel + initramfs files | One signed file, no unsigned initramfs on the ESP. | Our UKI build breaks on a major systemd or mkinitcpio change. |
| **Secure Boot** | Supported with user-enrolled keys via `sbctl`; not on by default | Ship a Microsoft-signed `shim` | Avoids the Microsoft signing process for v0. | Users ask for out-of-the-box Secure Boot on mainstream hardware. |
| **Installer (desktop)** | **Calamares** | Ubiquity (deprecated), a custom installer, `archinstall` | Mature GUI, modular, widely used by derivatives. | Calamares blocks a needed workflow, or is no longer maintained. |
| **Installer (minimal)** | **archinstall**, configured not forked | Scripted `pacstrap` only; custom TUI | Good defaults and a config file, no maintenance burden for us. | archinstall config becomes too awkward to keep Poop-specific. |
| **Desktop environment** | **KDE Plasma 6 on Wayland** (*Proposed*) | GNOME, XFCE, Sway (tiling) | Plasma is feature-rich, has a strong Wayland story, and ships a lot of configuration we can set as defaults. | Maintainers pick GNOME or a lighter DE for a different audience (see open question Q1). |
| **Display server** | **Wayland** first, Xwayland for legacy apps | X11 only | Modern default; Plasma supports it well. | An application we need has no Wayland path. |
| **Audio** | **PipeWire** + WirePlumber | PulseAudio, JACK-only | Default in the ecosystem, covers pro-audio and desktop use. | Never expected to change soon. |
| **Networking** | **NetworkManager** (+ `iwd` backend option) | `systemd-networkd`, `netctl` | Desktop-friendly, handles Wi-Fi and VPNs. | Minimal edition needs a leaner stack; then `systemd-networkd` becomes an option for that edition only. |
| **DNS / time** | **systemd-resolved**, **systemd-timesyncd** | dnsmasq, chrony | Built into systemd, sufficient for desktops. | Servers or high-precision time needs appear. |
| **Firewall** | **nftables** with a shipped ruleset (`poop-firewall`) | firewalld, ufw | Single backend, declarative file, no extra daemon for the default case. | Users need a GUI firewall manager as default (then firewalld as an optional package). |
| **LSM** | **AppArmor** | SELinux, none | Lower policy-maintenance burden; fits the Arch-style ecosystem. | Policy coverage is too thin to be useful; or a target market requires SELinux. |
| **Filesystem (minimal)** | **ext4** | btrfs, XFS | Simple and boring. | — |
| **Filesystem (desktop)** | **btrfs** + **snapper** + **snap-pac** | ZFS (licensing / DKMS), ext4 + timeshift | Snapshots before every upgrade, native to the kernel, no out-of-tree module. | Rollback UX needs to be boot-integrated (see §7). |
| **Privilege escalation** | **sudo** | doas, `run0` (systemd) | Most familiar, best-supported by tooling. | `run0` matures and is wanted by users. |
| **Shell (default login)** | **bash** | zsh, fish | Default for scripts and the widest compatibility. Users can change their shell in `poop-settings`. | — |
| **Core userspace** | GNU coreutils, util-linux, glibc | BusyBox, musl | Compatibility with everything we ship. | We build a size-constrained edition (then BusyBox/musl for that edition only). |
| **Containers** | **Podman** (rootless) | Docker | Daemonless, rootless by default, smaller attack surface. | Users need Docker Compose compatibility at scale (can ship `podman-compose` or the Docker-compatible socket). |
| **GUI apps** | **Flatpak** from Flathub | Snap, AppImage | Sandboxed, widely supported, no store lock-in. | Flathub policy changes or a required app is unavailable. |
| **Package signing** | `repo-add -s`, pacman `SigLevel Required` | Unsigned repos, TUF | Native pacman support, no extra infra. | We need a supply-chain framework (e.g. TUF/sigstore) for stronger guarantees. See §7. |
| **CI** | **GitHub Actions**: hosted runners for lint and unit checks; a **self-hosted Arch runner** for kernel, packages and ISOs | Only self-hosted; only hosted; Buildbot | Hosted runners cannot run privileged `mkarchiso`, so one self-hosted Arch runner is required. | Build volume outgrows one runner (add runners), or we need an isolated build environment (use ephemeral runners). |
| **Build orchestration** | **`make`** targets + bash scripts (`shellcheck`-clean) | `just`, Python tooling, Bazel | Available everywhere, no extra dependency for contributors. | The number of targets becomes hard to read; then `just` is a drop-in. |
| **Lint and checks** | `namcap`, `shellcheck`, `shfmt`, `yamllint`, `editorconfig-checker` | Custom linters | Standard tools, low maintenance. | — |
| **Boot tests** | QEMU + OVMF, scripted, with a serial-console success marker | Manual testing only | Automatable and repeatable, gates promotion. | We need hardware-in-the-loop tests (add a hardware lab). |
| **Package hosting** | Object storage origin behind a CDN (*Proposed*, see ADR-010) | GitHub Releases, a self-hosted server | Egress-heavy workload is cheap there; no server to run. GitHub Releases has per-file size limits and rate limits that make it a poor origin for ISOs. | Egress costs or provider limits change. |
| **Commit / PR conventions** | Conventional Commits; PR template in `.github/` | Free-form | Machine-readable changelog. | — |
| **Changelog** | Keep a Changelog (`CHANGELOG.md`) | Generated from commits only | Human-readable release notes. | Release volume makes hand-written notes unmanageable. |
| **Licensing** | Each package keeps its upstream license; repo scripts under a permissive license (*Proposed*: MIT) | Single license for all | Clean boundaries between kernel (GPL-2.0) and our tooling. | Legal review changes the policy. |
| **Branding** | Own name, logo and theme in `poop-branding`. No Arch logos or marks. | Keeping upstream branding | Avoids trademark confusion and keeps derivatives swappable. | — |

---

## 6. Trade-off analysis and decision log

Each decision below is an ADR. The full record (context, decision, consequences) goes in `docs/decisions/NNNN-<title>.md` when the decision is accepted. Trade-offs are listed here so the reasoning is in one place.

### ADR-001 — Base on Arch packaging (Accepted)

- **Options:** Arch packaging model; Buildroot; Debian live-build; Nix; from scratch (LFS-style).
- **Chosen:** Arch packaging model with `archiso` and `pacman`.
- **Gains:** largest maintained package set we can reuse; rolling updates; one package format; small toolchain.
- **Costs:** tied to Arch's conventions and release cadence. Our repo must track upstream Arch changes that break our packages (e.g. mkinitcpio, systemd). We cannot promise Arch compatibility guarantees for our own packages.
- **Team fit:** a small team can run it; the recipe format is well documented.

### ADR-002 — systemd as init (Accepted)

- **Gains:** the service set we ship assumes systemd; first-party units for everything in §5; ukify and resolved are systemd components.
- **Costs:** systemd is a large dependency, and some users actively prefer alternatives. We accept this in exchange for a much smaller configuration surface.

### ADR-003 — Reuse upstream Arch packages, override selectively (Accepted)

- **Gains:** almost all of the archive is available for free; our repo stays small.
- **Costs:** when an upstream package changes behaviour, we inherit it. Overrides must be justified and tracked in `repo/overrides.md` (to be created in Phase 1).

### ADR-004 — UEFI only in v0 (Proposed)

- **Gains:** one bootloader path, no legacy BIOS code paths, faster to test.
- **Costs:** machines without UEFI are unsupported. Those are rare in the target market, but not zero.

### ADR-005 — systemd-boot + signed UKI, not GRUB (Accepted)

- **Gains:** smaller, simpler, a single signed artifact per kernel, and clean Secure Boot with `sbctl`.
- **Costs:** no built-in snapshot boot menu, and no BIOS support. Both are noted in §3.4, §3.5 and §7.

### ADR-006 — Plasma 6 as the desktop default (Proposed, see Q1)

- **Gains:** rich defaults, strong Wayland support, good configurability for branding.
- **Costs:** heavier than GNOME-minimal or XFCE, and a bigger surface to maintain in the `poop-desktop` defaults.

### ADR-007 — Pin the kernel by SHA, no submodule, no vendoring (Accepted)

- **Gains:** reproducible builds, no 5 GiB tree in our repo, explicit upgrade commits.
- **Costs:** the bump is a manual step in `kernel/source.env`. CI makes this cheap by building the bump on every PR that touches it.

### ADR-008 — Two editions, not one (Accepted)

- **Gains:** a minimal CLI edition makes testing and server use simple; the desktop edition covers everyday users.
- **Costs:** two profiles and two installer configs to keep in sync. The shared `poop-base` package keeps the duplication low.

### ADR-009 — One self-hosted Arch runner for image builds (Accepted)

- **Gains:** `mkarchiso` works; builds are fast with warm caches.
- **Costs:** one machine is a single point of failure for releases. Users are not affected, because installed systems keep pulling from `poop-stable`. Mitigation: a second runner when volume requires it (§4.2).

### ADR-010 — Object storage origin behind a CDN for artifacts (Proposed)

- **Gains:** egress-heavy traffic is cheap, cacheable, and needs no servers.
- **Costs:** a vendor dependency, and an egress bill we must watch. Two origins are kept for failover (§4.3).

---

## 7. Revisit as the system grows

We will re-open these questions when the stated trigger happens. Each is an ADR candidate.

| Topic | Trigger | Likely direction |
|-------|---------|------------------|
| Kernel patch volume | Fork carries more than ~20 non-upstream patches, or upstream rebases start conflicting weekly | Dedicated `poop-release-<kver>` branches and a patch-queue tool |
| Legacy BIOS support | Users on pre-2012 hardware ask for it, or a target market needs it | Add GRUB as an optional bootloader package |
| Snapshot rollback in the boot menu | Users routinely need to roll back a bad upgrade | Boot-menu integration (systemd-boot entries for snapshots, or a GRUB-based path) |
| Out-of-box Secure Boot | Enough users run Secure Boot that enrolling keys is a support burden | Pursue a shim signing process, or document a guided enrolment flow |
| Supply-chain hardening | Repo grows past ~500 packages or we get a meaningful user base | Add TUF or sigstore attestations, reproducibility checks in CI |
| Architectures | Demand for aarch64 or RISC-V | New profile per arch; cross-building in CI |
| Immutable / atomic desktop | Maintenance of the mutable desktop becomes the main cost | Evaluate bootc/ostree-style image updates for an extra edition |
| Hosting | Egress bill grows past budget, or a provider changes terms | Move origin, add mirror network, or add torrent seeding |
| Init alternatives | A significant user group asks for a non-systemd edition | Build a separate variant, not a replacement |
| CI capacity | Kernel builds queue for more than a few hours | Add ephemeral runners, or split kernel builds onto their own runner |
| Team size | More than ~6 maintainers | Formal review rules in `CONTRIBUTING.md`, CODEOWNERS per directory |

---

## 8. Open questions

These need a decision from maintainers. Each one blocks a specific milestone (§9).

- **Q1 — Desktop default:** KDE Plasma 6 (recommended), GNOME, or no desktop default at all (desktop edition as a Plasma-only edition, with GNOME as an optional package).
- **Q2 — Base model:** Arch packaging (recommended, ADR-001), or a different base that changes everything in §2–§5.
- **Q3 — Init:** systemd (recommended, ADR-002), or a non-systemd default.
- **Q4 — Package hosting:** object storage + CDN (recommended, ADR-010), or GitHub Releases for v0 with migration later.
- **Q5 — Kernel features:** which fragments and patches go into v1 (LTO, scheduler changes, hardened options). Needs a benchmark plan before we commit.
- **Q6 — Signing custody:** who holds the offline master key, and how many custodians are needed to sign a keyring change.
- **Q7 — Naming and trademark:** confirm that "Poop Linux" and its branding are cleared for public use before the first public ISO.

---

## 9. Milestones

| Phase | Deliverable | Exit criteria |
|-------|-------------|---------------|
| 0 — Foundations | Repo skeleton, `Makefile`, lint CI, this design, `.gitignore` | `make lint` passes on `main`; CI green |
| 1 — Kernel | `linux-poop` from the pinned SHA, config fragments, headers | `makepkg` in a clean chroot; config drift check green |
| 2 — Packages | `poop-branding`, `poop-settings`, `poop-base`, `poop-firewall`, `poop-keyring`, signed `poop-testing` | Packages install on a clean Arch chroot; `namcap` clean |
| 3 — Minimal ISO | `profiles/minimal`, `archinstall` config | ISO boots in QEMU/OVMF; install completes; boot gate green |
| 4 — Desktop ISO | `profiles/desktop`, Calamares config, `poop-desktop` | Plasma session starts under QEMU; install with btrfs and snapper works |
| 5 — Release | `poop-stable`, CDN origins, changelog, first public ISO | Everything in §4.3 and §4.4 wired up; Q7 closed |

---

## 10. Glossary

- **PKGBUILD:** the build recipe for one package.
- **UKI:** Unified Kernel Image. A single signed EFI executable that bundles the kernel, the initramfs and the command line.
- **ukify:** systemd tool that builds UKIs.
- **archiso:** the tool set Arch uses to build its live ISO. We build our images with it.
- **Profile (archiso):** a directory that describes one ISO: packages, files and build options.
- **Pinned SHA:** a full git commit hash used as the source for a build, so the input can never change under us.
