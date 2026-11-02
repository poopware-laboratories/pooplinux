## What and why

<!-- What changed, and why. Link the issue or ADR if there is one. -->

## Type of change

- [ ] Bug fix
- [ ] Feature
- [ ] Recipe (new or changed package)
- [ ] Kernel (`kernel/`)
- [ ] Bootstrap order or stage change
- [ ] Installer / ISO / initramfs
- [ ] Documentation only
- [ ] CI or tooling
- [ ] Security fix (see note below)

## Checks run

<!-- Paste the real output or a short summary. Name any check you did not run and why. -->

- [ ] `make lint`
- [ ] Recipe checks (`make recipe-check R=<name>`) or sandbox build, if a recipe changed
- [ ] Kernel drift check (`make kernel-config-check`), if `kernel/` changed
- [ ] Boot test (`make test-boot`) or install test, if the image or installer changed
- [ ] Scenario tests in `tests/pkgmgr/`, if a component pin (`poop`, `poopsuite`, `musl-poop`) changed
- [ ] Benchmarks, if this PR makes a performance claim (table: workload, before median (min–max), after median (min–max), change; 5 or more runs)

## Sensitive areas

Does this PR touch any of these? If yes, say what the risk is and tag a second reviewer.

- [ ] CI workflows (`.github/workflows/`)
- [ ] Keyring or repo publish logic (`keyring/`, `repo/`)
- [ ] Signature verification or archive handling (in `pkgmgr`, via a pin bump)
- [ ] Kernel version or security-relevant kernel config
- [ ] Build sandbox (`sandbox/`)
- [ ] Installer that writes to disks (`installer/`)
- [ ] Default network or firewall policy

## Contracts and decisions

- [ ] This PR changes a contract in `ARCHITECTURE.md` §2.4, and `ARCHITECTURE.md` is updated in the same PR.
- [ ] This PR accepts or reverses a decision, and an ADR is added in `docs/decisions/`.
- [ ] `CHANGELOG.md` is updated under "Unreleased".

## Notes for reviewers

<!-- Anything a reviewer should look at first, known limitations, follow-up work. -->

---

**Security fixes:** do not describe a vulnerability in this PR, or in a public issue, before it is fixed. Report it through [SECURITY.md](../SECURITY.md) instead.

<!-- If an AI tool wrote a substantial part of this change, say so above and name the tool. -->

🤖 Generated with [Claude Code](https://claude.com/claude-code)
