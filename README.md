# Poop Linux

A from-scratch Linux distribution. The kernel comes from our fork, [`poopware-laboratories/linux`](https://github.com/poopware-laboratories/linux). Our other core components are ours too: the C library is our musl fork, [`musl-poop`](https://github.com/poopware-laboratories/musl-poop); init is [`poopsuite`](https://github.com/poopware-laboratories/poopsuite); the package manager is [`poop`](https://github.com/poopware-laboratories/poop). Everything else is built from upstream source by recipes in this repo.

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
| Know who maintains what | [`MAINTAINERS.md`](MAINTAINERS.md) |
| Follow the rules of conduct | [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) |
| See what changed | [`CHANGELOG.md`](CHANGELOG.md) |
| Report a security issue | [`SECURITY.md`](SECURITY.md). Do not open a public issue. |

## Quick start (contributors)

```bash
git clone git@github.com:poopware-laboratories/pooplinux.git
cd pooplinux
less ARCHITECTURE.md    # start here
```

Build targets (`make lint`, `make recipe-check`, `make iso`) arrive in Phases 0–5. See [`AGENTS.md` §5](AGENTS.md#5-commands) for the list.

## License

Our code, recipes and documentation: [BSD-3-Clause](LICENSE). The kernel is GPL-2.0-only, as upstream. Each upstream package keeps its own license.
