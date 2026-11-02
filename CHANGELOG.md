# Changelog

All notable changes to Poop Linux are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project does not yet use semantic versioning for the distribution as a whole. Packages carry their own upstream versions.

Entries go under **Unreleased** until a release is cut. Security fixes go under a **Security** heading in the release they ship in.

## [Unreleased]

### Added

- Architecture document (`ARCHITECTURE.md`) for a from-scratch, TTY-only distribution with its own package manager, C library and init.
- Contributor, agent and security documentation: `CONTRIBUTING.md`, `AGENTS.md`, `CLAUDE.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, `MAINTAINERS.md`.
- Project license: BSD-3-Clause (`LICENSE`).
- Repository `.gitignore` for build outputs, agent worktrees and key material.
- Pull request template and CODEOWNERS template under `.github/`.

### Changed

- Design revised from an Arch-packaging model to a from-scratch base built by our own recipes.
- Single edition `tty`. Desktop is out of scope for v0.
- C library is `musl-poop`, a fork of musl. Init is `poopsuite`. The package manager `pkgmgr` lives in `poopware-laboratories/poop`.

### Security

- None yet.
