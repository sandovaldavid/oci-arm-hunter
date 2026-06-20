---
layout: default
title: Getting Started
description: Step-by-step guide to set up and run oci-arm-hunter.
---

[Home](index) | Getting Started

---

## Prerequisites

### 1. Oracle Cloud Account

Sign up at [oracle.com/cloud/free](https://www.oracle.com/cloud/free/). You need a verified account — even the Always Free tier requires a credit card for identity verification.

### 2. Install oci-cli

```bash
# Oracle Linux / Fedora
sudo dnf install python3-oci-cli

# Ubuntu / Debian
pip install oci-cli

# Verify
oci --version
```

### 3. Configure oci-cli

```bash
oci setup config
```

This creates `~/.oci/config` with your tenancy credentials. When prompted, upload the generated public key (`~/.oci/oci_api_key_public.pem`) to your Oracle account under **Profile > API Keys**.

### 4. Install jq

```bash
# Ubuntu / Debian
sudo apt install jq

# Oracle Linux / Fedora
sudo dnf install jq
```

---

## Setup Wizard

```bash
make setup
```

The wizard runs interactively and does the following automatically:

| Step | What happens |
|------|-------------|
| 1 | Reads `TENANCY_OCID` from `~/.oci/config` |
| 2 | Fetches all Availability Domains for your region |
| 3 | Lists compartments — you pick one |
| 4 | Lists VCNs and subnets — you pick the public subnet |
| 5 | Lists ARM-compatible images — you pick your OS |
| 6 | Prompts for your SSH public key (paste from Bitwarden or key file) |
| 7 | Optional: instance name, notification URL, cooldown range |
| 8 | Writes `.env` to the project root |

> **Tip:** Get your SSH public key from Bitwarden's SSH Agent — copy the public key and paste it when prompted. The private key never leaves Bitwarden.

---

## Running the Hunter

### Foreground (watch live output)

```bash
make run
```

Press `Ctrl+C` to stop.

### Background with tmux (recommended for laptops)

```bash
make run-bg      # launches detached tmux session named "cazador"
make logs        # reconnect to follow the log
make stop        # kill the session when done
```

### Systemd service (recommended for VM Micro)

If you're running on an existing **VM.Standard.E2.1.Micro** (also Always Free), install as a service so it survives reboots:

```bash
make install

# Monitor
sudo journalctl -fu cazador-arm

# Uninstall
make uninstall
```

---

## Notifications

When the VM is claimed, the hunter sends a `curl` POST to `NOTIFY_URL` with the instance ID and public IP.

### ntfy.sh (no account required)

1. Install the **ntfy** app on your phone (Android / iOS)
2. Subscribe to a unique topic, e.g. `my-arm-hunter-2026`
3. Set in `.env`:

```bash
NOTIFY_URL="https://ntfy.sh/my-arm-hunter-2026"
```

---

## Connecting to your VM

Once the instance is running:

```bash
ssh ubuntu@<public-ip>      # Ubuntu images
ssh opc@<public-ip>         # Oracle Linux images
```

If you stored your SSH key in Bitwarden, make sure the **Bitwarden SSH Agent** is active — it signs the SSH handshake using the private key in memory without writing it to disk.

---

[Back to Home](index)
