# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) and Claude on how to work in this repo, any repo, and on my machines: which tools to prefer, what environment to assume, and hard guardrails it must follow.

---

## General workflow

- Always prefer using the `gh` CLI for GitHub actions wherever possible (creating PRs, checking status, viewing checks, etc.) instead of doing these in the browser. If there is a reasonable way to do it with `gh`, default to that.

- Commit messages do not need to be long or highly detailed. Aim for a short, clear summary of what changed (for example: `fix: handle null user id` or `feat: add basic auth middleware`). Avoid walls of text, but include enough signal that future‑you can tell what happened at a glance.

- After addressing PR comments, you can resolve the comment thread yourself if you have fixed or intentionally addressed the feedback. If you are unsure whether something is fully resolved, leave the thread open and reply with context instead.

---

## Local dev tools

We use two main tools for local dev environments: `wut` for feature/issue branches inside a repo, and `try` for ad‑hoc experiments and scratch work.

Both `wut` and `try` are already installed and configured via my dotfiles, including shell integration, so you can assume their commands and `init` hooks are available in interactive shells.

### wut – ephemeral worktrees for repo features

When working on new features or issues, prefer using Git worktrees to isolate your changes whenever it feels appropriate. In this repo, we use the [`wut`](https://github.com/simonbs/wut) CLI to make creating and managing ephemeral worktrees fast and low‑friction.

Use `wut` when you are doing structured work that will turn into a branch/PR in this repo.

**Worktree workflow with wut:**

1. From the main repo directory, create a new worktree for your branch:

   - For a new feature: `wut new feature-<short-description>`
   - For a bugfix: `wut new fix-<short-description>`
   - You can optionally base it off another ref:
     `wut new feature-<short-description> --from other-branch-or-sha`

2. `wut` will:

   - Create a new branch with the given name (unless it already exists)
   - Create a corresponding worktree under `.worktrees/<branch-name>`
   - Automatically `cd` you into that worktree (shell integration is already set up in dotfiles)

3. Do all work related to that feature or issue inside the worktree:

   - Edit, commit, and push from the worktree directory as you normally would
   - Keep each worktree focused on a single feature/issue to avoid cross‑contamination of changes

4. When you are done and your branch is merged (or no longer needed), clean up the worktree:

   - `wut rm <branch-name>`
   - This will remove the worktree directory and delete the branch (unless you pass `--force` for edge cases)

5. To jump between worktrees and the main repo:

   - `wut list` to see existing worktrees
   - `wut go` to switch back to the main worktree (usually `main`)
   - `wut go <branch-name>` to jump into a specific worktree

`wut` keeps all worktrees in a `.worktrees/` directory in the repo root and automatically ensures they are ignored by Git. For more details and advanced usage (autocompletion, fzf integration, etc.), see the wut README: https://github.com/simonbs/wut

### try – scratch experiments, spikes, and quick repos

We also use [`try`](https://github.com/tobi/try) for quick experiments and ad‑hoc worktrees outside the main long‑lived branches.

Use `try` when you want to:

- Spin up a short‑lived experiment or spike
- Clone a repo just to poke at it
- Create a one‑off worktree for something that does not need to live under `.worktrees/` in this repo

By default (as configured in dotfiles), `try` keeps experiments in a single directory (usually `~/src/tries`), with date‑prefixed names like `2026-02-09-new-api`.

**Experiment workflow with try:**

- Basic usage for greenfield experiments:

  - `try`
    Opens the TUI to browse all existing experiments and jump into one.

  - `try <keyword>`
    Fuzzy‑searches your existing experiments and lets you jump into one or create a new one with that name (auto‑prefixed with today’s date, like `2026-02-09-new-api`).

- Git repo experiments and cloning:

  - `try clone https://github.com/user/repo.git`
    Clones the repo into a date‑prefixed directory (for example `2026-02-09-user-repo`) and jumps into it.

  - `try https://github.com/user/repo.git`
    Shorthand for the same clone behavior.

  Use these when you want to try out a repo, test a branch, or explore an upstream project without polluting your main projects directory.

- Worktrees via try:

  - From inside an existing Git repo:

    - `try . [name]`
      Creates a dated directory for a detached‑HEAD Git worktree based on the current repo and jumps into it. The directory name defaults to the repo’s basename, date‑prefixed, unless you pass a custom `[name]`.

    - `try worktree dir [name]`
      Explicit form of the same behavior, useful in scripts.

  Use this when you want a one‑off, short‑lived worktree for an experiment that does not need to be managed by `wut` or live inside the repo’s `.worktrees` folder.

You can assume `try` is available with shell integration and a configured experiments path; no additional setup is needed in individual repos.

---

## Rails scaffolding and Homebrew tap

### boxcar – Rails app generator

When suggesting new Rails apps or services, prefer using my [`boxcar`](https://github.com/jaspermayone/boxcar) template rather than `rails new` directly.

- `boxcar` is installed via my personal Homebrew tap as `boxcar`.
- It provides my opinionated defaults for Rails apps (deployment, gems, structure, etc.), so new Rails projects should assume this template unless there is a strong reason not to.

Typical usage for a new Rails app:

- `boxcar new <app-name>`
- Then follow any setup instructions in the generated README / scripts.

Claude should assume:

- New Rails services or prototypes start from `boxcar`.
- If modifying or extending an existing Rails app created with `boxcar`, respect its existing conventions rather than suggesting a completely different structure.

### Homebrew tap and custom tools

I maintain a personal Homebrew tap at [`jaspermayone/homebrew-tap`](https://github.com/jaspermayone/homebrew-tap), which is already tapped on my machines:

- `brew tap jaspermayone/tap`

From this tap:

- `boxcar` – Rails app generator (see above).
- `zipmerge` (cask) – macOS app for merging zip files.

When suggesting installs or updates for these tools:

- Prefer `brew install jaspermayone/tap/boxcar` for `boxcar`.
- Prefer `brew install --cask zipmerge` for ZipMerge rather than manual downloads.

Claude should assume these are already installed on my main dev machine unless explicitly stated otherwise, and avoid redundant installation instructions.

---

## Environment and dotfiles

This repo lives on machines managed by my Nix‑based dotfiles: [`jaspermayone/dots`](https://github.com/jaspermayone/dots). Those dotfiles define almost all of my tools, shells, and defaults.

On my primary dev machine **remus** (macOS, nix‑darwin), the dotfiles repo is checked out at:

- `/Users/jsp/dev/dots`

Claude should assume:

- remus is the main development environment, configured via the `remus` host in `dots`, and changes to global tools/services should go through that flake.
- Secrets and tokens are managed with `agenix` in `dots` (no hard‑coding secrets into config or examples).
- Common tools (`wut`, `try`, `gh`, Nix, Home Manager, `bore`, `frp`, status services, etc.) are already installed and wired up by the flake and Home Manager configs.
- Shell configuration (prompt, aliases, `wut`, `try`, `gh`, etc.) comes from the `home` and `rc` modules in `dots`, so suggestions can rely on those being available in interactive shells.

When proposing changes that touch system configuration, services, or global tooling, prefer:

- Editing the appropriate Nix module in `dots` (for example under `hosts/`, `modules/`, or `home/`) and rebuilding via `nix flake` / `darwin-rebuild` / `nixos-rebuild`, rather than one‑off manual changes.
- Adding new system‑level tools or services via the `dots` flake, not ad‑hoc `brew install` / manual installers, unless explicitly noted as temporary.

For anything involving tunnels, status pages, or VPS config, treat **alastor** as the central NixOS host, managed entirely through the `dots` repo.

---

## Guardrails

### Dotfiles / Nix guardrails

My environment is managed by my Nix‑based dotfiles repo [`jaspermayone/dots`](https://github.com/jaspermayone/dots).

On my main dev machine (**remus**, macOS nix‑darwin) this repo lives at `/Users/jsp/dev/dots`. These configs are the source of truth for system packages, services, shells, and most tooling. They should be treated as infrastructure, not a scratchpad.

When suggesting changes that touch dotfiles or Nix config:

- Prefer small, targeted edits with clear context over broad refactors.
- Assume changes should be made via:
  - `/Users/jsp/dev/dots/flake.nix`
  - `/Users/jsp/dev/dots/hosts/remus/...`
  - `/Users/jsp/dev/dots/home/...`
  - `/Users/jsp/dev/dots/modules/...`
  - `/Users/jsp/dev/dots/packages/...`
- Always show the exact file path and the full before/after snippet for any proposed edit, so it is easy to review.

Hard guardrails:

- Do not propose sweeping or automated rewrites of the dotfiles (no “just search and replace across the repo”, no mass renames).
- Do not remove existing options, modules, or hosts unless the instruction explicitly says to decommission them.
- Do not suggest writing secrets or tokens directly into Nix files or shell configs. Use `agenix` secrets as defined in `dots/secrets/` instead.
- Do not recommend bypassing Nix/dots with one‑off global changes (`brew install`, editing raw `~/.zshrc`, etc.) unless explicitly described as a temporary workaround.

When installing new tools or services globally:

- Prefer adding them to the appropriate Nix module in `/Users/jsp/dev/dots` and rebuilding (for example with `darwin-rebuild switch --flake /Users/jsp/dev/dots#remus`) instead of ad‑hoc installs.

### Git / commits guardrails

Claude must never create or apply Git commits without my explicit sign‑off.

- Do not run or suggest running commands that create commits automatically (for example `git commit`, `git commit -am`, `jj commit`, or tools that auto‑commit as part of their workflow) unless I have explicitly asked for a commit with a specific message.
- When proposing changes, only:
  - Show diffs / patches, or
  - Suggest the commands I could run myself.

I will always review changes before committing. Claude’s job is to propose edits (files, hunks, commands), not to decide when something is ready to be committed.

### Secrets / .env guardrails

Claude must never read or inspect secrets (API keys, tokens, passwords, etc.) without explicit permission.

Hard rules:

- Do not open, read, or ask to see:
  - `.env` files
  - `.env.*` variants
  - `secrets.*` files
  - `*.age` or other encrypted secret blobs
  - Any file or path clearly used for secrets/credentials
- Do not suggest commands that print or expose secrets (for example `cat .env`, `cat secrets.*`, `printenv` dumps) unless I have explicitly asked for that exact action.

If a task might involve secrets:

- Ask for a non‑secret representation instead (for example “show me the variable names, not the values”).
- Assume you should work with placeholders like `YOUR_API_KEY_HERE` and documented env var names, not real values.
- If I explicitly grant permission to look at a secret file, limit access to only what is needed and never log, echo, or reuse those values outside the immediate context.