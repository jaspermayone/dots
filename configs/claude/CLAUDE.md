# CLAUDE.md

Guidance for Claude Code and Claude on this repo and my machines.

---

## General Workflow

- Use `gh` CLI for GitHub actions (PRs, checks, status) over the browser whenever possible.
- Commit messages: short Conventional Commits format (`feat:`, `fix:`, `chore:`, etc.). No walls of text.
- After addressing PR comments, resolve the thread yourself if fully fixed. Leave it open with context if unsure.

---

## Local Dev Tools

Both `wut` and `try` are installed via dotfiles with shell integration. Assume they're available.

### wut — ephemeral worktrees

Use for structured work that becomes a branch/PR.

- `wut new feature-<name>` / `wut new fix-<name>` — creates branch + worktree under `.worktrees/`, cds in.
- `wut new <name> --from <ref>` — base off another branch or SHA.
- `wut list` / `wut go [branch]` — navigate worktrees.
- `wut rm <branch>` — clean up when done.

Keep each worktree focused on one feature/issue.

### try — scratch experiments

Use for spikes, one-off clones, or experiments that don't belong in `.worktrees/`.

- `try` — opens TUI to browse existing experiments.
- `try <keyword>` — fuzzy-find or create a date-prefixed experiment (`2026-02-09-keyword`).
- `try clone <url>` / `try <url>` — clone a repo into a dated directory.
- `try . [name]` — detached-HEAD worktree from the current repo.

Experiments live in `~/src/tries` by default.

---

## Rails and Homebrew

### boxcar

Use [`boxcar`](https://github.com/jaspermayone/boxcar) instead of `rails new` for all new Rails apps. Installed via my Homebrew tap.

- `boxcar new <app-name>`
- Respect existing `boxcar` conventions in apps already generated with it.

### Homebrew tap

Tap: `jaspermayone/tap` (already tapped on my machines).

- `brew install jaspermayone/tap/boxcar`
- `brew install --cask zipmerge`

Assume these are installed. Skip redundant install instructions.

---

## Environment and Dotfiles

Machines are managed by [`jaspermayone/dots`](https://github.com/jaspermayone/dots) (Nix/nix-darwin). Dotfiles live at `/Users/jsp/dev/dots` on **remus** (primary dev machine, macOS).

Assume:
- All common tools (`wut`, `try`, `gh`, Nix, Home Manager, etc.) are wired up by the flake.
- Secrets are managed with `agenix`. Never hard-code secrets.
- Shell config comes from `home`/`rc` modules in `dots`.
- **alastor** is the central NixOS VPS host for tunnels, status pages, and VPS config.

For system-level changes, prefer editing the appropriate Nix module and rebuilding (`darwin-rebuild switch --flake /Users/jsp/dev/dots#remus`), not one-off installs.

---

## Guardrails

### Dotfiles / Nix

Treat `dots` as infrastructure. When touching Nix config:

- Make small, targeted edits. Show exact file path and before/after snippet.
- Relevant paths: `flake.nix`, `hosts/remus/`, `home/`, `modules/`, `packages/`.
- Do not mass-rewrite, mass-rename, or remove hosts/modules unless explicitly told to decommission them.
- Do not write secrets into Nix files. Use `agenix` via `dots/secrets/`.
- Do not suggest bypassing Nix with `brew install` or editing `~/.zshrc` unless explicitly a temporary workaround.

### Secrets

Never read or inspect secrets without explicit permission.

- Do not open `.env`, `.env.*`, `secrets.*`, `*.age`, or any credential file.
- Do not suggest commands that print secrets (`cat .env`, `printenv` dumps, etc.) unless explicitly asked.
- Work with placeholder names (`YOUR_API_KEY_HERE`) and documented env var names, not real values.
- If granted access to a secret file, use only what's needed and never log or reuse values.

---

## Task Delegation

Spawn subagents to isolate context, parallelize work, or offload bulk tasks. Don't spawn when the parent needs the reasoning or synthesis requires holding context together.

Model selection:
- **Haiku**: bulk mechanical work, no judgment needed.
- **Sonnet**: scoped research, code exploration, in-scope synthesis.
- **Opus**: subtasks needing real planning or tradeoffs.

Rules: Haiku does not spawn further subagents. Max spawn depth is 2. Don't escalate tiers without a concrete reason — return to parent instead. Parent owns final output.

---

## Preferred Tools

### Data Fetching

1. **WebFetch** — default for public pages.
2. **agent-browser CLI** — for dynamic pages or auth walls. Returns accessibility tree with element refs. Install: `npm i -g agent-browser && agent-browser install`.
3. When the same fetch/parse pattern recurs, propose wrapping it as a named tool.

### PDFs

Use `pdftotext`. Use `Read` only when explicitly asked to analyze images or charts in the document.

---

## Commits and Pull Requests

### Commit format

- [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`.
- Branch naming with issue number: `jaspermayone/<issue-number>-<short-name>`.
- No `Co-Authored-By` trailers. No Claude/Anthropic attribution.

### Pre-commit checklist

- Formatter run, linting passes, type checking passes, tests pass.
- Docs updated where appropriate. Use Mermaid for flows and schemas.
- All changes require test coverage.

### Pull requests

- PR titles: Conventional Commit format, lowercase.
- Use Mermaid diagrams in PR descriptions where appropriate.
- Add `migration` label if the PR includes database migrations.
- No "Generated with Claude Code" footers or Claude/Anthropic attribution in PR bodies.
