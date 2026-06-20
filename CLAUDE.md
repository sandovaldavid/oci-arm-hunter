# CLAUDE.md

## Conventional Commits — Scope Table

Scope is **required** on every commit. Derive it from this table.

| Scope | Applies to |
|-------|-----------|
| `hunter` | `cazador.sh` — retry loop, OCI instance launch logic |
| `setup` | `setup.sh` — interactive configuration wizard |
| `make` | `Makefile` — targets and automation |
| `docs` | `README.md`, `CONTRIBUTING.md`, `docs/` |
| `ci` | `.github/workflows/`, release-please config |
| `config` | `.env.example`, `.commitlintrc.json`, manifests |
| `repo` | Repo-level files: `LICENSE`, issue templates, PR template |

## Project Structure

```
cazador.sh          Main retry loop — loads .env, calls OCI API
setup.sh            Interactive wizard — generates .env via oci-cli
Makefile            Single entry point: make setup | run | run-bg | logs | install
.env.example        Config template
docs/               Technical plan + Jekyll website source
.github/workflows/  CI (shellcheck, commitlint), release-please, GitHub Pages
```

## Key Conventions

- Shell scripts: `bash` with `set -euo pipefail`
- OCI API errors captured with `|| { error "msg"; echo "$output"; exit 1; }`
- All OCI commands go through `oci-cli` (never curl directly to OCI API)
- `.env` is never committed (in `.gitignore`)
- SSH public key lives in `.env` (not secret); private key stays in Bitwarden
