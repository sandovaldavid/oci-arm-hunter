---
layout: default
title: OCI ARM Hunter
description: Claim your Oracle Cloud ARM Always Free instance automatically — no console required.
---

[![CI](https://github.com/sandovaldavid/oci-arm-hunter/actions/workflows/ci.yml/badge.svg)](https://github.com/sandovaldavid/oci-arm-hunter/actions/workflows/ci.yml)
[![Latest Release](https://img.shields.io/github/v/release/sandovaldavid/oci-arm-hunter)](https://github.com/sandovaldavid/oci-arm-hunter/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/sandovaldavid/oci-arm-hunter/blob/main/LICENSE)

Oracle's ARM Always Free tier (`VM.Standard.A1.Flex` — 2 OCPUs / 12 GB RAM) is almost always out of capacity. **oci-arm-hunter** retries the OCI API continuously until your instance is available, then claims it and notifies you — all without touching the web console.

> **Important Update (June 2026):** Oracle Cloud has reduced the Always Free Ampere A1 Compute limits to **2 OCPUs and 12 GB RAM** per tenancy. If you are using a Pay As You Go (PAYG) account to bypass capacity limits, make sure to configure `OCPUS=2` and `MEMORY_GB=12` in your `.env` to prevent unexpected charges.

---

## What it does

- **Interactive setup** — runs `make setup` to fetch all OCI resource IDs automatically via `oci-cli`
- **Persistent retry loop** — rotates Availability Domains with randomized cooldown jitter
- **Instant notification** — push alert via ntfy.sh (or any webhook) the moment your VM is claimed
- **Unattended 24/7** — runs as a `systemd` service or `tmux` session on an existing Micro VM

---

## Quick Start

```bash
git clone https://github.com/sandovaldavid/oci-arm-hunter.git
cd oci-arm-hunter
make setup    # interactive wizard — fetches OCIDs automatically
make run-bg   # launch in background (tmux)
make logs     # follow live progress
```

---

## Make Targets

| Command | Description |
|---------|-------------|
| `make setup` | Interactive wizard to generate `.env` |
| `make run` | Launch hunter in foreground |
| `make run-bg` | Launch in persistent tmux session |
| `make logs` | Follow live log |
| `make status` | Check if hunter is running |
| `make stop` | Stop the tmux session |
| `make install` | Install as systemd service |
| `make uninstall` | Remove systemd service |

---

## Prerequisites

- [`oci-cli`](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm) configured with API key credentials
- `jq` — `apt install jq` / `dnf install jq`
- `tmux` — for background execution

---

## Notifications

```bash
# .env
NOTIFY_URL="https://ntfy.sh/your-unique-topic"
```

Install the [ntfy app](https://ntfy.sh/) on your phone. No account required.

---

[View on GitHub](https://github.com/sandovaldavid/oci-arm-hunter){: .btn}
[Getting Started](getting-started){: .btn}
