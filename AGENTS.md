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
| `custom/base` | last upstream release tag | The last upstream release tag (currently `1.3.39-g8d2844f`) plus only the fork's housekeeping files (this file, `.claude/rules/custom-fork.md`). |
| `feat/*`, `fix/*` | `custom/base` | One self-contained, generic change each, written so it can be offered upstream. |
| `custom/main` | `custom/base` | Integration branch: `custom/base` plus merges of the feature branches. Releases are built only from here. |

- Upstream PR from a feature branch: `git rebase --onto upstream/develop custom/base <branch>` into a separate PR branch, so the housekeeping commit is not included.
- Updating upstream: fetch the new upstream release tag, rebase `custom/base` onto it, rebase the feature branches onto `custom/base`, rebuild `custom/main` from `custom/base` by merging the feature branches again, and rebuild the release with the new tag as base (see Releases). `develop` is kept as a plain upstream mirror.
- When upstream merges one of our changes, drop that feature branch from `custom/main`.

## Changes

- Keep every change generic and opt-in (new CLI options or flags with upstream defaults unchanged). Anything specific to a downstream product lives in that product's repository, not here.
- Current feature branches:
  - `feat/msi-upgrade-code`: option to set the MSI UpgradeCode explicitly instead of deriving it from the pack id.
  - `feat/msi-per-machine-strict`: option for a per-machine-only MSI: launch condition requiring an elevated per-machine install (no `ALLUSERS`/`MSIINSTALLPERUSER` override), fixed install folder under Program Files (no `VELOPACK_INSTALLDIR`, no public directory property).
  - `feat/msi-media-template`: opt-in MSI cabinet compression and automatic embedded cabinet splitting (`--msiCompression`).
  - `feat/msi-fragment`: option to include an additional WiX fragment file in the generated MSI.

## Releases

- `version.json` on `custom/main` pins the version to `<base major.minor.patch>-custom.N` (e.g. `1.3.39-custom.1`); bump `N` on every release. Never publish packages under upstream's package ids to public feeds (nuget.org etc.).
- Custom release versions use an explicit zero revision in `version.json` (e.g. `1.3.39.0-custom.2`) to prevent Git height from changing the CLI version. NuGet and the CLI normalize the zero revision away; the commit is retained in assembly metadata.
- The custom changes are managed (C#) only. A custom release is the official upstream binaries of the base tag (native helpers inside the `vpk` package, and the separate `velopack_libc` SDK) plus the custom managed code. Do not build or replace Rust/native binaries unless a change needs it.
- Build the `vpk` tool package with `custom/build-vpk.ps1` (Windows, PowerShell 7, .NET SDK, no Rust). It takes the native helpers from the official upstream `vpk` package of `-UpstreamVersion`, packs them next to the custom managed code, checks that they are byte-identical to the official ones, and smoke-tests the result. Record the base tag in the release notes.
- Consumers keep `major.minor.patch` of the tool and of the `velopack_libc` SDK equal (both come from the same base tag).
- Release tags: `v<version>` on `custom/main`, e.g. `v1.3.39-custom.1`. Release assets: the nupkg and `SHA256SUMS`.
