# Git Mirror Synchronizer - Manual

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Notification](#notification)
- [Usage](#usage)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

---

## Overview

Git Mirror Synchronizer is a shell-based tool that:

- Syncs Git repositories from upstream sources
- Mirrors changes to multiple remote destinations
- Downloads GitHub release artifacts and tag archives
- Supports automated scheduling via cron

---

## Prerequisites

- **Shell**: Zsh, **Git**, **jq**, **curl**

**Install dependencies:**

| Platform      | Command                                |
|---------------|----------------------------------------|
| Debian/Ubuntu | `sudo apt-get install jq git curl zsh` |
| RHEL/Fedora   | `sudo dnf install jq git curl zsh`     |
| macOS         | `brew install jq git curl`             |

---

## Installation

```bash
git clone https://github.com/LockonS/git-mirror-synchronizer.git
cd git-mirror-synchronizer
mkdir -p data/github temp log
chmod +x sync-tool.sh

# Set up default storage (optional)
sudo mkdir -p /opt/git/{git-repo,git-release,git-tag}
sudo chown -R $USER:$USER /opt/git
```

---

## Configuration

### Configuration Hierarchy

Settings are merged in this order (later overrides earlier):

```
config/config.global.json  →  data/config.json  →  data/repo.json (per-repo)
```

### Global Default — `config/config.global.json`

```json
{
  "repo": {
    "storagePath": "/opt/git/git-repo",
    "sync": "true"
  },
  "release": {
    "storagePath": "/opt/git/git-release",
    "download": "true",
    "keptVersionNum": "5"
  },
  "tag": {
    "storagePath": "/opt/git/git-tag",
    "download": "true",
    "keptVersionNum": "5"
  },
  "notification": {
    "email": ""
  }
}
```

| Field                   | Description                                          |
|-------------------------|------------------------------------------------------|
| `*.storagePath`         | Base directory for storing repos / releases / tags   |
| `*.sync` / `*.download` | Enable or disable the operation (`"true"`/`"false"`) |
| `*.keptVersionNum`      | Number of versions to retain                         |
| `notification.email`    | Email address to receive sync result notifications. Leave empty to disable. |

### Custom Global — `data/config.json`

Override any global defaults for your environment:

```json
{
  "repo": {
    "storagePath": "/custom/path/repos"
  },
  "release": {
    "download": "false"
  },
  "notification": {
    "email": "admin@example.com"
  }
}
```

### Repository List — `data/repo.json` *(required)*

An array of repository objects:

```json
[
  {
    "repoUrl": "https://github.com/user/repo.git",
    "identifier": "user/repo",
    "catalog": "tools/automation",
    "repo": {
      "sync": "true"
    },
    "release": {
      "download": "true",
      "keptVersionNum": "5",
      "excludeKeywords": "windows,arm64"
    },
    "tag": {
      "download": "true",
      "keptVersionNum": "5"
    },
    "mirror": [
      {
        "name": "gitlab",
        "repoUrl": "git@gitlab.example.com:mirror/repo.git",
        "forcePush": "false"
      }
    ]
  }
]
```

**Key fields:**

| Field                     | Required | Description                                                 |
|---------------------------|----------|-------------------------------------------------------------|
| `repoUrl`                 | ✓        | Upstream repository URL                                     |
| `identifier`              | —        | Custom `owner/name` label (auto-extracted if omitted)       |
| `catalog`                 | —        | Subdirectory path for organizing storage (e.g. `tools/cli`) |
| `repo`, `release`, `tag`  | —        | Per-repo overrides (inherit from global if omitted)         |
| `release.excludeKeywords` | —        | Comma-separated keywords to skip release assets             |
| `mirror[].forcePush`      | —        | Force-push to mirror (`"true"`/`"false"`)                   |

### Notification

When `notification.email` is set, a sync report is sent to that address after each run.  
Configure it in `data/config.json` (or `config/config.global.json`) at the global level:

```json
{
  "notification": {
    "email": "admin@example.com"
  }
}
```

Leave the value empty (`""`) to disable email notifications.

**Storage paths with catalog:**

```
{storagePath}/{catalog}/{identifier}/
```

Without `catalog`, falls back to `{storagePath}/{identifier}/` (backward compatible).

### GitHub Access Token

Avoids API rate limits (60 req/hr unauthenticated):

```bash
echo "your_token_here" > data/github/github-access-token
chmod 600 data/github/github-access-token
```

Generate a token at: GitHub → Settings → Developer settings → Personal access tokens (`public_repo` scope).

---

## Usage

```bash
./sync-tool.sh [OPTIONS]
```

### Options

| Option       | Description                                             |
|--------------|---------------------------------------------------------|
| `-f FILE`    | Custom global config file (default: `data/config.json`) |
| `-d FILE`    | Repository data file (default: `data/repo.json`)        |
| `-r URL`     | Process a single repository by URL                      |
| `-s INDEX`   | Start index, 0-based inclusive                          |
| `-e INDEX`   | End index, 0-based exclusive                            |
| `-m MODE`    | Execution mode (see below)                              |
| `--dry-run`  | Preview operations without executing                    |
| `--continue` | Resume from last saved progress                         |
| `-h`         | Show help                                               |

### Execution Modes

| Mode              | Repo Clone/Pull | Mirror Sync | Release | Tag |
|-------------------|:---------------:|:-----------:|:-------:|:---:|
| `all` *(default)* |        ✓        |      ✓      |    ✓    |  ✓  |
| `update`          |        ✓        |      ✗      |    ✗    |  ✗  |
| `sync`            |        ✓        |      ✓      |    ✗    |  ✗  |
| `release`         |        ✗        |      ✗      |    ✓    |  ✗  |
| `tag`             |        ✗        |      ✗      |    ✗    |  ✓  |

### Common Commands

```bash
./sync-tool.sh                            # Sync everything
./sync-tool.sh --dry-run                  # Preview only
./sync-tool.sh -m sync                    # Repo + mirrors, no downloads
./sync-tool.sh -m release                 # Download releases only
./sync-tool.sh -m tag                     # Download tags only
./sync-tool.sh -m update                  # Local pull only
./sync-tool.sh --continue                 # Resume interrupted run
./sync-tool.sh -s 0 -e 25                 # Process first 25 repos (batch)
./sync-tool.sh -f custom.json -d repos.json  # Custom config files
```

**Batch processing** (split 100 repos into 4 parallel runs):

```bash
./sync-tool.sh -s 0  -e 25 
./sync-tool.sh -s 25 -e 50 
./sync-tool.sh -s 50 -e 75 
./sync-tool.sh -s 75      
```

> `--continue` saves progress to `temp/progress-index` and deletes it on successful completion.

---

## Examples

### Basic repo + mirror sync

```json
[
  {
    "repoUrl": "https://github.com/torvalds/linux.git",
    "catalog": "kernel",
    "mirror": [
      {
        "name": "backup",
        "repoUrl": "git@gitserver.com:backup/linux.git"
      }
    ]
  }
]
```

### Release downloads with filters

```json
[
  {
    "repoUrl": "https://github.com/kubernetes/kubernetes.git",
    "catalog": "cloud/k8s",
    "repo": {
      "sync": "false"
    },
    "release": {
      "download": "true",
      "excludeKeywords": "darwin,windows"
    }
  }
]
```

### Multiple mirrors

```json
{
  "repoUrl": "https://github.com/user/project.git",
  "catalog": "projects/critical",
  "mirror": [
    {
      "name": "primary",
      "repoUrl": "git@gitlab.com:backup/project.git",
      "forcePush": "false"
    },
    {
      "name": "secondary",
      "repoUrl": "git@gitlab.elsewhere.com:backup/project.git",
      "forcePush": "true"
    },
    {
      "name": "local-nas",
      "repoUrl": "git@nas.local:backup/project.git",
      "forcePush": "false"
    }
  ]
}
```

### Cron job

```bash
# Linux example
0 2 * * * cd /path/to/git-mirror-synchronizer/sync-tool.sh
```

---

## Troubleshooting

| Problem                             | Solution                                                     |
|-------------------------------------|--------------------------------------------------------------|
| `Config file does not exist`        | Run `mkdir -p data` and create `data/repo.json`              |
| `jq: command not found`             | Install jq: `brew install jq` / `apt-get install jq`         |
| GitHub API rate limit exceeded      | Add a token to `data/github/github-access-token`             |
| Permission denied on storage path   | `sudo chown -R $USER:$USER /opt/git` or change `storagePath` |
| Mirror push failed                  | Verify SSH access: `ssh -T git@gitlab.example.com`           |
| Repository clone fails              | Check connectivity, credentials, and disk space (`df -h`)    |

---

## Best Practices

- **Test first** — always use `--dry-run` before applying config changes
- **Token security** — set `chmod 600` on `data/github/github-access-token`; never commit it
- **SSH keys** — use dedicated keys for automation, not personal keys
- **Disk space** — monitor `/opt/git` when downloading releases; set `keptVersionNum` accordingly
- **Log rotation** — rotate `/var/log/git-mirror-sync.log` with `logrotate` to avoid disk growth
- **Batching** — use `-s`/`-e` to parallelize large repository lists
- **Start small** — verify with 1–2 repos before scaling up
