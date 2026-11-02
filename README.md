# Poop Linux

A from-scratch Linux distribution. The kernel comes from our fork, [`poopware-laboratories/linux`](https://github.com/poopware-laboratories/linux). Every other package is built from upstream source by recipes in this repo, and installed and upgraded by our own package manager, `pkgmgr` (working name).

> **Status: pre-alpha.** Nothing here is ready to install. The repository currently holds the design and the contributor documentation. The first milestone is a text-console system, bootstrapped from the live ISO, that boots in QEMU.

## Edition

| Edition | For | Interface |
|---------|-----|-----------|
| `tty` | Everyone, for now | Text console only. No desktop. |

## Where to look

| If you want to… | Read |
|-----------------|------|
| Understand the design and why it is built this way | [`ARCHITECTURE.md`](ARCHITECTURE.md) |
| Contribute code, recipes or docs | [`CONTRIBUTING.md`](CONTRIBUTING.md) |
| Use an AI coding agent in this repo | [`AGENTS.md`](AGENTS.md) (and [`CLAUDE.md`](CLAUDE.md) for Claude Code) |
| See what changed | [`CHANGELOG.md`](CHANGELOG.md) *(to be created)* |
| Report a security issue | [`CONTRIBUTING.md` §13](CONTRIBUTING.md#13-security-issues). Do not open a public issue. |

## Quick start (contributors)

```bash
git clone git@github.com:poopware-laboratories/pooplinux.git
cd pooplinux
less ARCHITECTURE.md    # start here
```

Build targets (`make lint`, `make build`, `make iso`) arrive in Phases 0–5. See [`AGENTS.md` §5](AGENTS.md#5-commands) for the list.

## License

Our code, recipes and documentation: [BSD-3-Clause](LICENSE). The kernel is GPL-2.0-only, as upstream. Each upstream package keeps its own license.
