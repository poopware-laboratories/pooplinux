# Poop Linux

A Linux distribution built on our kernel fork, [`poopware-laboratories/linux`](https://github.com/poopware-laboratories/linux). The rest of the system uses the Arch Linux packaging model: PKGBUILDs, `pacman`, and `archiso`.

> **Status: pre-alpha.** Nothing here is ready to install. The repository currently holds the design and the contributor documentation. The first milestone is a minimal ISO that boots in QEMU.

## Editions (planned)

| Edition | For | Desktop |
|---------|-----|---------|
| `minimal` | Servers, containers, people who want a CLI | none |
| `desktop` | Everyday use | KDE Plasma 6 on Wayland *(proposed, see `ARCHITECTURE.md` Q1)* |

## Where to look

| If you want to… | Read |
|-----------------|------|
| Understand the design and why it is built this way | [`ARCHITECTURE.md`](ARCHITECTURE.md) |
| Contribute code, docs or packages | [`CONTRIBUTING.md`](CONTRIBUTING.md) |
| Use an AI coding agent in this repo | [`AGENTS.md`](AGENTS.md) (and [`CLAUDE.md`](CLAUDE.md) for Claude Code) |
| See what changed | [`CHANGELOG.md`](CHANGELOG.md) *(to be created)* |
| Report a security issue | [`CONTRIBUTING.md` §13](CONTRIBUTING.md#13-security-issues). Do not open a public issue. |

## Quick start (contributors)

```bash
git clone git@github.com:poopware-laboratories/pooplinux.git
cd pooplinux
less ARCHITECTURE.md    # start here
```

Build targets (`make lint`, `make kernel`, `make iso`) arrive in Phase 0 and Phase 3. See [`AGENTS.md` §5](AGENTS.md#5-commands) for the list.

## License

Kernel: GPL-2.0 (upstream). Repository tooling and documentation: license to be confirmed by maintainers (see `ARCHITECTURE.md` §5). Each package keeps its upstream license.
