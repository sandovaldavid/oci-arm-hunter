# Contributing to oci-arm-hunter

## Branch Strategy

```
main      stable releases  (v1.0.0, v1.1.0, ...)
develop   beta releases    (v1.0.0-beta.0, v1.0.0-beta.1, ...)
feat/*    new features     → PR to develop
fix/*     bug fixes        → PR to develop
docs/*    documentation    → PR to develop
```

All PRs target `develop`. Releases to `main` are managed automatically by release-please.

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

## Pull Request Process

1. Fork the repo and create a branch from `develop`
2. Make your changes with conventional commit messages
3. Open a PR targeting `develop`
4. CI must pass (ShellCheck + commitlint)
5. Squash merge — PR title becomes the commit message, so it must also follow conventional commits format

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
