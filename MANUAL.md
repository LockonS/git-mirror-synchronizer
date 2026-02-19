# Git Mirror Synchronizer - Usage Manual

## Table of Contents
- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)
- [Advanced Configuration](#advanced-configuration)

---

## Overview

Git Mirror Synchronizer is a shell-based automation tool designed to:
- Track and sync Git repositories from upstream sources
- Mirror changes to multiple remote repositories
- Download GitHub release artifacts and tags
- Maintain local backups with automated updates

### Key Features
- **Multi-repository management**: Handle multiple repositories with a single configuration
- **Multiple mirror support**: Sync each repository to multiple mirror destinations
- **GitHub integration**: Download release assets and tag archives automatically
- **Flexible configuration hierarchy**: Global defaults with per-repository overrides
- **Automated scheduling**: Designed for cron job integration
- **Cross-platform**: Supports both Linux and macOS

---

## Prerequisites

### Required Software
- **Shell**: Zsh (Z shell)
- **Git**: Version control system
- **jq**: JSON processor for parsing configuration files
- **curl**: For downloading GitHub releases

### Installing Dependencies

**Debian/Ubuntu:**
```bash
sudo apt-get install jq git curl zsh
```

**RHEL/Fedora/CentOS:**
```bash
sudo dnf install jq git curl zsh
```

**macOS:**
```bash
brew install jq git curl
```

### Storage Requirements
- Default storage location: `/opt/git/`
- Ensure sufficient disk space for repositories and release artifacts
- Write permissions for the configured storage paths

---

## Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/LockonS/git-mirror-synchronizer.git
   cd git-mirror-synchronizer
   ```

2. **Create necessary directories:**
   ```bash
   mkdir -p data/github
   mkdir -p temp
   mkdir -p log
   ```

3. **Set up storage directories (if using defaults):**
   ```bash
   sudo mkdir -p /opt/git/git-repo
   sudo mkdir -p /opt/git/git-release
   sudo mkdir -p /opt/git/git-tag
   sudo chown -R $USER:$USER /opt/git
   ```

4. **Make the script executable:**
   ```bash
   chmod +x sync-tool.sh
   ```

---

## Configuration

### Configuration Hierarchy

The tool uses a three-tier configuration system with the following merge priority:

```
repo.json (per-repo) > data/config.json (custom global) > config/config.global.json (default global)
```

Configurations are merged using deep copy, where later configurations override earlier ones.

### 1. Global Default Configuration

File: `config/config.global.json`

This file contains the default settings for all repositories:

```json
{
  "repo": {
    "storagePath": "/opt/git/git-repo",
    "sync": "true"
  },
  "release": {
    "storagePath": "/opt/git/git-release",
    "download": "true",
    "keptVersionNum": "3"
  },
  "tag": {
    "storagePath": "/opt/git/git-tag",
    "download": "true",
    "keptVersionNum": "3"
  }
}
```

**Configuration Fields:**

- **repo.storagePath**: Base directory for storing cloned repositories
- **repo.sync**: Enable/disable repository synchronization ("true"/"false")
- **release.storagePath**: Base directory for downloaded release artifacts
- **release.download**: Enable/disable release downloads ("true"/"false") 
- **release.keptVersionNum**: Number of release versions to retain
- **tag.storagePath**: Base directory for downloaded tag archives
- **tag.download**: Enable/disable tag downloads ("true"/"false")
- **tag.keptVersionNum**: Number of tag versions to retain

### 2. Custom Global Configuration

File: `data/config.json` (automatically generated based on default global config)

Create this file to override global defaults for your environment:

```json
{
  "repo": {
    "storagePath": "/custom/path/repos"
  },
  "release": {
    "download": "false"
  }
}
```

This file merges with and overrides values from `config/config.global.json`.

### 3. Repository Configuration

File: `data/repo.json` (required)

This file defines the list of repositories to manage. It's a JSON array of repository objects:

```json
[
  {
    "repoUrl": "https://github.com/user/repository.git",
    "identifier": "user/repository",
    "catalog": "category/subcategory",
    "repo": {
      "storagePath": "/opt/git/git-repo",
      "sync": "true"
    },
    "release": {
      "storagePath": "/opt/git/git-release",
      "download": "true",
      "keptVersionNum": "3",
      "excludeKeywords": "windows,arm64"
    },
    "tag": {
      "storagePath": "/opt/git/git-tag",
      "download": "true",
      "keptVersionNum": "3"
    },
    "mirror": [
      {
        "name": "gitlab",
        "repoUrl": "git@gitlab.example.com:mirror/user/repository.git",
        "forcePush": "false"
      }
    ]
  }
]
```

**Repository Configuration Fields:**

**Required:**
- **repoUrl**: URL of the upstream repository to track

**Optional:**
- **identifier**: Custom identifier (e.g., "owner/repo-name"). If not specified, extracted from repoUrl
- **catalog**: Category path for organizing repositories, releases, and tags (e.g., "tools", "projects/web")
  - Repository path: `{repo.storagePath}/{catalog}/{identifier or repo-name}`
  - Release path: `{release.storagePath}/{catalog}/{identifier}/{version}`
  - Tag path: `{tag.storagePath}/{catalog}/{identifier}/{tag-name}`
  - If catalog is not set, paths fall back to: `{storagePath}/{identifier}` (backward compatible)
- **repo**: Repository sync settings (inherits from global if not specified)
  - **storagePath**: Override storage location
  - **sync**: Enable/disable sync for this repo
- **release**: Release download settings (inherits from global if not specified)
  - **storagePath**: Override release storage location  
  - **download**: Enable/disable release downloads
  - **keptVersionNum**: Number of versions to keep
  - **excludeKeywords**: Comma-separated keywords to exclude release assets
- **tag**: Tag download settings (inherits from global if not specified)
  - **storagePath**: Override tag storage location
  - **download**: Enable/disable tag downloads
  - **keptVersionNum**: Number of versions to keep
- **mirror**: Array of mirror repositories
  - **name**: Remote name for the mirror (e.g., "gitlab", "backup1")
  - **repoUrl**: URL of the mirror repository
  - **forcePush**: Use force push ("true"/"false")

### 4. GitHub Access Token

For downloading releases and avoiding API rate limits:

1. **Generate a GitHub Personal Access Token:**
   - Go to GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
   - Generate a token with `public_repo` scope (or `repo` for private repos)

2. **Save the token:**
   ```bash
   echo "your_github_token_here" > data/github/github-access-token
   chmod 600 data/github/github-access-token
   ```

**Note:** Without a GitHub token, API rate limits (60 requests/hour) may be reached quickly.

---

## Usage

### Command Syntax

```bash
./sync-tool.sh [OPTIONS]
```

### Available Options

| Option | Alias | Description |
|--------|-------|-------------|
| `-f FILE` | `--config-file FILE` | Specify custom global configuration file (default: `data/config.json`) |
| `-d FILE` | `--data-file FILE` | Specify repository data file (default: `data/repo.json`) |
| `-m MODE` | `--mode MODE` | Execution mode: `all` (default), `update`, `sync`, `release`, `tag` |
| `--dry-run` | - | Preview operations without executing |
| `--continue` | - | Resume processing from the last saved progress index |
| `-h` | `--help`, `help` | Display help manual |

### Execution Modes

| Mode | Repo Clone/Pull | Mirror Sync | Release Download | Tag Download |
|------|----------------|-------------|------------------|--------------|
| `all` (default) | ✓ | ✓ | ✓ | ✓ |
| `update` | ✓ | ✗ | ✗ | ✗ |
| `sync` | ✓ | ✓ | ✗ | ✗ |
| `release` | ✗ | ✗ | ✓ | ✗ |
| `tag` | ✗ | ✗ | ✗ | ✓ |

- **`all`**: Runs all enabled operations as defined in the configuration.
- **`update`**: Clones or pulls repositories only; skips mirror sync and all downloads.
- **`sync`**: Clones/pulls repositories and pushes to all configured mirrors; skips downloads.
- **`release`**: Downloads GitHub release assets only; skips repository and tag operations.
- **`tag`**: Downloads GitHub tag archives only; skips repository and release operations.

### Resume / Continue Mode

When processing a large list of repositories, the tool saves progress after each completed repository to `temp/progress-index`. If the run is interrupted, you can resume from where it left off:

```bash
./sync-tool.sh --continue
```

- Progress is tracked per-run and stored in `temp/progress-index`.
- On successful completion, the progress file is automatically deleted.
- `--continue` can be combined with `-m`, `-f`, `-d`, and `--dry-run`.
- If no saved progress exists, the run starts from the beginning.

### Basic Usage

**Sync all repositories with default configuration:**
```bash
./sync-tool.sh
```

**Sync with custom configuration files:**
```bash
./sync-tool.sh -f /path/to/custom-config.json -d /path/to/custom-repos.json
```

**Preview operations without executing:**
```bash
./sync-tool.sh --dry-run
```

**Sync repositories only (no downloads):**
```bash
./sync-tool.sh -m sync
```

**Download releases only:**
```bash
./sync-tool.sh -m release
```

**Download tags only:**
```bash
./sync-tool.sh -m tag
```

**Update local repos only (no mirror sync, no downloads):**
```bash
./sync-tool.sh -m update
```

**Resume an interrupted run:**
```bash
./sync-tool.sh --continue
```

**Resume an interrupted run in a specific mode:**
```bash
./sync-tool.sh --continue -m sync
```

---

## Examples

### Example 1: Basic Setup

1. **Create repository configuration:**

```bash
cat > data/repo.json << 'EOF'
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
EOF
```

2. **Run the sync:**
```bash
./sync-tool.sh
```

### Example 2: Download Releases Only

```bash
cat > data/repo.json << 'EOF'
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
EOF
```

### Example 3: Multiple Mirrors with Force Push

```json
[
  {
    "repoUrl": "https://github.com/user/important-project.git",
    "catalog": "projects/critical",
    "mirror": [
      {
        "name": "gitlab-primary",
        "repoUrl": "git@gitlab.com:backup/important-project.git",
        "forcePush": "false"
      },
      {
        "name": "gitlab-secondary",
        "repoUrl": "git@gitlab.elsewhere.com:backup/important-project.git",
        "forcePush": "true"
      },
      {
        "name": "local-nas",
        "repoUrl": "git@nas.local:backup/important-project.git",
        "forcePush": "false"
      }
    ]
  }
]
```

### Example 4: Custom Storage Paths

```json
[
  {
    "repoUrl": "https://github.com/large/repository.git",
    "catalog": "large-projects",
    "repo": {
      "storagePath": "/mnt/large-drive/repos",
      "sync": "true"
    },
    "release": {
      "storagePath": "/mnt/large-drive/releases",
      "download": "true"
    }
  }
]
```

### Example 5: Automated Daily Sync with Cron

**Linux (using `/var/log`):**
```bash
# Edit crontab
crontab -e

# Add this line to run at 2:00 AM daily
0 2 * * * cd /path/to/git-mirror-synchronizer && ./sync-tool.sh 2>&1 | tee -a /var/log/git-mirror-sync.log
```

**macOS (using user directory):**
```bash
# Edit crontab
crontab -e

# Add this line to run at 2:00 AM daily
0 2 * * * cd /path/to/git-mirror-synchronizer && ./sync-tool.sh 2>&1 | tee -a ~/.git-mirror-sync/git-mirror-sync.log
```

### Example 6: Organization-wide Backup

```json
[
  {
    "repoUrl": "https://github.com/myorg/web-frontend.git",
    "catalog": "myorg/frontend",
    "repo": { "sync": "true" },
    "release": { "download": "true" },
    "mirror": [{"name": "backup", "repoUrl": "git@backup.local:myorg/web-frontend.git"}]
  },
  {
    "repoUrl": "https://github.com/myorg/api-backend.git",
    "catalog": "myorg/backend",
    "repo": { "sync": "true" },
    "release": { "download": "true" },
    "mirror": [{"name": "backup", "repoUrl": "git@backup.local:myorg/api-backend.git"}]
  },
  {
    "repoUrl": "https://github.com/myorg/mobile-app.git",
    "catalog": "myorg/mobile",
    "repo": { "sync": "true" },
    "release": { "download": "true" },
    "mirror": [{"name": "backup", "repoUrl": "git@backup.local:myorg/mobile-app.git"}]
  }
]
```

---

## Troubleshooting

### Common Issues

#### 1. "Config file does not exist"
**Problem:** Configuration files not found.

**Solution:**
```bash
# Check if files exist
ls -la data/repo.json
ls -la data/config.json

# Create data directory if missing
mkdir -p data

# Create minimal repo.json
cp template/repo-example.json data/repo.json
```

#### 2. "jq: command not found"
**Problem:** JSON processor not installed.

**Solution:**
```bash
# Debian/Ubuntu
sudo apt-get install jq

# macOS
brew install jq
```

#### 3. GitHub API Rate Limit Exceeded
**Problem:** Too many GitHub API requests without authentication.

**Solution:**
```bash
# Add GitHub access token
mkdir -p data/github
echo "your_token_here" > data/github/github-access-token
chmod 600 data/github/github-access-token
```

#### 4. Permission Denied on Storage Path
**Problem:** No write access to configured directories.

**Solution:**
```bash
# Change ownership (adjust user/group as needed)
sudo chown -R $USER:$USER /opt/git

# Or use a different path you own
vim data/config.json
# Update storagePath to a directory you own
```

#### 5. Mirror Push Failed
**Problem:** Authentication or network issues pushing to mirrors.

**Solution:**
```bash
# Test SSH access to mirror  
ssh -T git@gitlab.example.com

# Ensure SSH keys are configured
ssh-add -l

# Check git remote configuration
cd /path/to/local/repo
git remote -v
git push mirror-name --dry-run
```

#### 6. Repository Clone Fails
**Problem:** Unable to clone upstream repository.

**Solution:**
```bash
# Test connectivity
git clone https://github.com/user/repo.git /tmp/test-clone

# Check if you need authentication
# For private repos, use SSH URL or configure credentials

# Check disk space
df -h /opt/git
```

#### 7. "readlink: illegal option" on macOS
**Problem:** macOS uses BSD readlink, not GNU readlink.

**Solution:**
```bash
# Install GNU coreutils
brew install coreutils

# Update PATH or modify sync-tool.sh to use greadlink
```

---

## Advanced Configuration

### Organizing Repositories with Catalogs

Use the `catalog` field to organize repositories hierarchically:

```json
[
  {
    "repoUrl": "https://github.com/a/tool1.git",
    "catalog": "tools/automation"
  },
  {
    "repoUrl": "https://github.com/b/tool2.git",
    "catalog": "tools/monitoring"
  },
  {
    "repoUrl": "https://github.com/c/app1.git",
    "catalog": "projects/web"
  },
  {
    "repoUrl": "https://github.com/d/app2.git",
    "catalog": "projects/mobile"
  }
]
```

**Resulting directory structure:**
```
/opt/git/git-repo/
├── tools/
│   ├── automation/
│   │   └── tool1/
│   └── monitoring/
│       └── tool2/
└── projects/
    ├── web/
    │   └── app1/
    └── mobile/
        └── app2/

/opt/git/git-release/
├── tools/
│   ├── automation/
│   │   └── tool1/
│   │       └── v1.0.0/
│   └── monitoring/
│       └── tool2/
│           └── v2.1.0/
└── projects/
    ├── web/
    │   └── app1/
    │       └── v3.0.0/
    └── mobile/
        └── app2/
            └── v1.5.0/

/opt/git/git-tag/
├── tools/
│   ├── automation/
│   │   └── tool1/
│   │       └── v1.0.0/
│   └── monitoring/
│       └── tool2/
│           └── v2.1.0/
└── projects/
    ├── web/
    │   └── app1/
    │       └── v3.0.0/
    └── mobile/
        └── app2/
            └── v1.5.0/
```

**Note:** All three storage types (repositories, releases, and tags) now use the same catalog-based hierarchy for consistent organization.

### Exclude Keywords for Release Downloads

Filter out unwanted release assets using keywords:

```json
{
  "repoUrl": "https://github.com/user/cross-platform-tool.git",
  "release": {
    "download": "true",
    "excludeKeywords": "windows,darwin,arm64,debug,src"
  }
}
```

Assets with any of these keywords in the filename will be skipped.

### Custom Identifiers

Override the automatic identifier extraction:

```json
{
  "repoUrl": "https://github.com/very-long-organization-name/very-long-repository-name.git",
  "identifier": "org/repo",
  "catalog": "tools"
}
```

**Result:** Repository stored at `/opt/git/git-repo/tools/org/repo` instead of the much longer auto-generated path.

### Force Push Configuration

Use force push when you need to overwrite mirror history:

```json
{
  "mirror": [
    {
      "name": "mirror",
      "repoUrl": "git@gitlab.com:user/repo.git",
      "forcePush": "true"
    }
  ]
}
```

**Warning:** Force push will overwrite remote history. Use with caution and only when necessary (e.g., recovering from diverged histories).

### Selective Sync and Download

Fine-tune what operations to perform per repository:

```json
[
  {
    "repoUrl": "https://github.com/a/repo1.git",
    "catalog": "active",
    "repo": { "sync": "true" },
    "release": { "download": "false" },
    "tag": { "download": "false" }
  },
  {
    "repoUrl": "https://github.com/b/repo2.git",
    "catalog": "archive",
    "repo": { "sync": "false" },
    "release": { "download": "true" },
    "tag": { "download": "true" }
  }
]
```

### Log Management

**Log files are automatically created at:**
- **Linux (with write access):** `/var/log/git-mirror-sync.log`
- **Linux (without write access):** `~/.local/state/git-mirror-sync/mirror-sync.log`
- **macOS:** `~/.git-mirror-sync/git-mirror-sync.log`

**Set up log rotation (Linux):**

```bash
sudo tee /etc/logrotate.d/git-mirror-sync << 'EOF'
/var/log/git-mirror-sync.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0644 $USER $USER
}
EOF
```

### Monitoring Sync Status

**Create a status check script:**

```bash
#!/bin/bash
# check-sync-status.sh

REPO_BASE="/opt/git/git-repo"

for repo in $(find "$REPO_BASE" -name .git -type d); do
    repo_dir=$(dirname "$repo")
    echo "Repository: $repo_dir"
    cd "$repo_dir"
    
    # Check for uncommitted changes
    if [[ -n $(git status -s) ]]; then
        echo "  ⚠️  Uncommitted changes detected"
    fi
    
    # Check if ahead/behind upstream
    git fetch origin --quiet 2>/dev/null
    behind=$(git rev-list --count HEAD..@{u} 2>/dev/null)
    ahead=$(git rev-list --count @{u}..HEAD 2>/dev/null)
    
    if [[ $behind -gt 0 ]]; then
        echo "  ⚠️  Behind origin by $behind commits"
    fi
    if [[ $ahead -gt 0 ]]; then
        echo "  ⚠️  Ahead of origin by $ahead commits"
    fi
    
    if [[ $behind -eq 0 ]] && [[ $ahead -eq 0 ]]; then
        echo "  ✓ In sync with origin"
    fi
    echo ""
done
```

---

## Directory Structure

### After Setup

```
git-mirror-synchronizer/
├── LICENSE
├── MANUAL.md                    # This file
├── readme.md                    # Quick start guide
├── sync-tool.sh                 # Main executable
├── component/
│   ├── common.sh                # Common utilities (colors, etc.)
│   ├── environment.sh           # Environment variables
│   └── operation.sh             # Core operations
├── config/
│   └── config.global.json       # Global default configuration
├── data/
│   ├── config.json              # Custom global configuration (optional)
│   ├── repo.json                # Repository list (required)
│   └── github/
│       └── github-access-token  # GitHub API token
├── module/
│   ├── module-github.sh         # GitHub-specific operations
│   ├── module-gitlab.sh         # GitLab support (placeholder)
│   └── module-gitee.sh          # Gitee support (placeholder)
├── template/
│   └── repo-example.json        # Repository configuration example
├── log/                         # Local log files  
└── temp/                        # Temporary files (auto-created)
```

### Storage Directories (Default)

```
/opt/git/
├── git-repo/                    # Synchronized repositories
│   └── {catalog}/
│       └── {identifier or name}/
├── git-release/                 # Downloaded release artifacts
│   └── {catalog}/
│       └── {identifier}/
│           └── {version}/
│               └── {assets}
└── git-tag/                     # Downloaded tag archives
    └── {catalog}/
        └── {identifier}/
            └── {tag-name}/
                └── {tag-name}.tar.gz
```

**Note:** Releases and tags now follow the same catalog-based organization as repositories. If a repository does not have a catalog defined, the old flat structure `{storagePath}/{identifier}/{version}` is used for backward compatibility.

---

## Best Practices

1. **Start Small**: Begin with 1-2 repositories and expand after verifying the setup
2. **Regular Backups**: Ensure mirror destinations are also backed up
3. **Token Security**: Protect your GitHub access token with appropriate file permissions (600)
4. **Disk Space Monitoring**: Monitor available disk space, especially when downloading releases
5. **Test with Dry-Run**: Use `--dry-run` to verify configuration changes before applying
6. **Log Retention**: Implement log rotation to prevent disk space issues
7. **Network Considerations**: Consider network bandwidth when scheduling sync operations
8. **Error Notifications**: Set up email notifications for cron job failures
9. **SSH Key Management**: Use dedicated SSH keys for automated operations
10. **Documentation**: Keep notes on custom configurations and why specific settings were chosen

---

## Performance Tips

1. **Parallel Execution**: For many repositories, consider running multiple instances in parallel
2. **Shallow Clones**: For large repositories you only need recent history, modify the clone command
3. **Exclude Large Files**: Configure `.gitattributes` to handle large files appropriately
4. **Network Optimization**: Use local mirrors or caches for frequently accessed repositories
5. **Incremental Backups**: Rely on Git's incremental nature rather than full backups

---

## Security Considerations

1. **Access Tokens**: Store tokens securely and use the minimum necessary permissions
2. **SSH Keys**: Use separate SSH keys for automation, not your personal keys
3. **File Permissions**: Ensure configuration files have appropriate permissions (600 or 640)
4. **Network Security**: Use SSH for mirrors when possible instead of HTTPS with tokens
5. **Secrets Management**: Never commit access tokens or SSH keys to version control
6. **Regular Audits**: Periodically review what repositories are being synced and where

---

## Contributing

Contributions are welcome! When contributing:
- Test changes thoroughly with `--dry-run`
- Follow existing shell script conventions
- Update documentation for new features
- Ensure backward compatibility when possible

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) file for details.

---

## Support

For issues, questions, or feature requests:
1. Check this manual and the [readme.md](readme.md)
2. Review the [Troubleshooting](#troubleshooting) section
3. Check existing issues on the project repository
4. Open a new issue with detailed information

---

**Version:** 2.1  
**Last Updated:** February 19, 2026
