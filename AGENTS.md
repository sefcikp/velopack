# Custom fork rules

This repository is a public fork of [velopack/velopack](https://github.com/velopack/velopack). These rules apply to every person and agent working in it, on any machine. Upstream's own guidance in `CLAUDE.md` still applies; do not edit `CLAUDE.md` (it is upstream's file and edits would conflict on every sync).

## Naming

- Never mention the internal product, company or any downstream project name anywhere in this repository: branch names, commit messages, code, comments, docs, version strings, tags, PR/issue texts.
- The fork's own things are called `custom`: branch `custom/main`, version suffix `-custom.N`, etc.
- Before every commit and push, check the diff and the message for such names.

## Branches

| Branch | Base | Purpose |
|---|---|---|
| `develop` | `upstream/develop` | Exact mirror of upstream. Never commit to it; update with GitHub "Sync fork" or `git fetch upstream && git merge --ff-only upstream/develop`. |
| `custom/base` | `develop` | `develop` plus only the fork's housekeeping files (this file, `.claude/rules/custom-fork.md`). |
| `feat/*`, `fix/*` | `custom/base` | One self-contained, generic change each, written so it can be offered upstream. |
| `custom/main` | `custom/base` | Integration branch: `custom/base` plus merges of the feature branches. Releases are built only from here. |

- Upstream PR from a feature branch: `git rebase --onto upstream/develop custom/base <branch>` into a separate PR branch, so the housekeeping commit is not included.
- Updating upstream: update `develop`, rebase `custom/base` onto it, rebase the feature branches onto `custom/base`, rebuild `custom/main` from `custom/base` by merging the feature branches again.
- When upstream merges one of our changes, drop that feature branch from `custom/main`.

## Changes

- Keep every change generic and opt-in (new CLI options or flags with upstream defaults unchanged). Anything specific to a downstream product lives in that product's repository, not here.
- Current feature branches:
  - `feat/msi-upgrade-code`: option to set the MSI UpgradeCode explicitly instead of deriving it from the pack id.
  - `feat/msi-per-machine-strict`: option for a per-machine-only MSI: launch condition requiring an elevated per-machine install (no `ALLUSERS`/`MSIINSTALLPERUSER` override), fixed install folder under Program Files (no `VELOPACK_INSTALLDIR`, no public directory property).
  - `feat/msi-fragment`: option to include an additional WiX fragment file in the generated MSI.

## Releases

- `version.json` on `custom/main` produces `-custom.N` versions; never publish packages under upstream's package ids to public feeds.
- Build `vpk` (with its embedded `Update.exe`) and the native libraries from the same `custom/main` commit; consumers require matching versions.
