# Contributing to oci-arm-hunter

## Branch Strategy

| Origin Branch | Target Branch | Merge Strategy | Purpose |
|---|---|---|---|
| `feat/*`, `fix/*`, `refactor/*`, `docs/*` | `develop` | **Squash Merge** | Keeps `develop` history linear, clean, and free of WIP commit noise. |
| `develop` | `main` | **Merge Commit (`--no-ff`)** | Groups changes into a "Release" version, preserving the history of individual features. |
| `hotfix/*` | `main` & `develop` | **Merge Commit** or **Squash** | Resolves critical production issues immediately, with prompt backport to `develop`. |

### Branch Protection & GitHub Configuration

To enforce this workflow, configure the following settings in your repository hosting platform (e.g. GitHub):

1. **For the `develop` branch protection rules:**
   - **Require a pull request before merging:** Enabled.
   - **Require status checks to pass before merging:** Enabled (requires `CI` workflows: `ShellCheck` and `Commitlint` to pass).
   - **Allowed merge methods (Repository Settings):** Restrict merging into `develop` to **Squash Merge** only.

2. **For the `main` branch protection rules:**
   - **Require a pull request before merging:** Enabled.
   - **Require status checks to pass before merging:** Enabled (`CI` workflows).
   - **Allowed merge methods (Repository Settings):** Allow **Merge Commits** (`--no-ff`) for merging `develop` into `main`.

All PRs target `develop` during normal feature work. Releases from `develop` to `main` are triggered via a PR and managed automatically by `release-please` once merged.

## Commit Format

This project enforces [Conventional Commits](https://www.conventionalcommits.org/). Scope is **required**.

```
type(scope): imperative description
```

### Valid scopes

| Scope | Applies to |
|-------|-----------|
| `hunter` | `cazador.sh` — retry loop logic |
| `setup` | `setup.sh` — configuration wizard |
| `make` | `Makefile` — targets |
| `docs` | `README.md`, `CONTRIBUTING.md`, `docs/` |
| `ci` | `.github/workflows/`, release-please |
| `config` | `.env.example`, commitlint, manifests |
| `repo` | repo-level files (LICENSE, templates) |

### Examples

```bash
feat(hunter): add exponential backoff on TooManyRequests
fix(setup): handle LimitExceeded when creating VCN
docs(docs): add ntfy.sh configuration example
chore(ci): upgrade release-please-action to v4
```

## Pull Request & Release Process

### Feature & Fix Development (to `develop`)
1. Fork the repo and create a branch from `develop` (e.g. `feat/my-feature` or `fix/my-bug`).
2. Make your changes with Conventional Commit messages.
3. Open a PR targeting `develop`.
4. CI must pass (ShellCheck + commitlint).
5. Merge using **Squash Merge** only. The PR title will become the squashed commit message on `develop`, so ensure it follows the Conventional Commit format (e.g., `feat(hunter): add exponential backoff`).

### Release to Production (from `develop` to `main`)
1. Once features are tested and ready on `develop`, open a PR from `develop` targeting `main`.
2. Ensure CI passes.
3. Merge using **Normal Merge / Merge Commit (`--no-ff`)** only. Do **not** squash. This keeps all individual feature commits in the history of `main` for proper release-please changelog generation.

### Hotfixes (to `main` & `develop`)
1. For critical production fixes, branch directly from `main` (e.g., `hotfix/critical-patch`).
2. Open a PR targeting `main`.
3. Merge using **Normal Merge** or **Squash Merge**.
4. Immediately backport the changes to `develop` (via cherry-pick or PR) to ensure `develop` receives the fix.

## Development Setup

```bash
git clone https://github.com/sandovaldavid/oci-arm-hunter.git
cd oci-arm-hunter
git checkout develop

# Validate shell scripts locally
shellcheck cazador.sh setup.sh
```

## Reporting Issues

Use the issue templates — bug reports and feature requests each have their own form.
