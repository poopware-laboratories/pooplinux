# CLAUDE.md

Claude Code reads this file on every session in this repository. The shared agent rules are in `AGENTS.md`, imported below. Do not copy them here. Edit `AGENTS.md` instead.

@AGENTS.md

---

## Claude Code specifics

These notes apply only to Claude Code sessions. They do not change the rules in `AGENTS.md`.

### Working copies

- Make code changes in a **git worktree** under `.claude/worktrees/`, never in the shared checkout at the repository root. The directory is git-ignored.
- The repo's `main` branch may have no commits when you start. If `git worktree add` from `HEAD` fails for that reason, create an orphan branch with `git worktree add --orphan -b <branch> .claude/worktrees/<name>`. Do not create an empty commit on `main` to get around this.
- Commit when the work is done. Push the branch if `origin` exists. Never push to `main` or `master`.

### Design work

- For architecture questions, read `ARCHITECTURE.md` first. If a decision there is marked *Proposed*, ask before building on it. If it is *Accepted*, follow it, and say so if you think it should change.
- For larger features, write a plan in `docs/decisions/` or in the PR before writing code.

### Asking for decisions

- When a fork in the task needs a maintainer decision, ask with a short multiple-choice question. Put the recommended option first and mark it *(Recommended)*.
- Do not ask about choices that `ARCHITECTURE.md` already settles, or that a reasonable default covers. Make the default, note it in your report, and keep going.

### Skills that help in this repo

| Need | Skill |
|------|-------|
| Architecture change or new subsystem | `engineering:architecture`, `engineering:system-design` |
| Reviewing a diff before a PR | `engineering:code-review` |
| Test strategy for kernel, packages or boot | `engineering:testing-strategy` |
| Release steps and rollback plan | `engineering:deploy-checklist` |
| Documentation pass on `ARCHITECTURE.md` or `CONTRIBUTING.md` | `engineering:documentation` |
| Long-running reference lookups (kernel docs, Arch packaging rules) | `Explore` agent, with a narrow question |
