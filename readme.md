## Git Mirror Synchronizer

📖 **[Complete Usage Manual](MANUAL.md)** - Comprehensive guide with examples, troubleshooting, and advanced configuration

- This is a shell script for automating the repetitive work of tracking repositories and syncing them to mirror destinations.
- **Principle**: What this script does is straightforward:
    1. Clones or updates local repositories from upstream sources
    2. Pushes updates to configured mirror repositories
    3. Optionally downloads GitHub release artifacts and tags

> **Scenario**  
> I've got a self-hosted git server and need to back up repositories from GitHub while keeping them up-to-date automatically. A simple shell script triggered by crontab is enough to do the job. As the tracking list grows, this script keeps everything neat and organized.  
> I'd be happy if this script also helps others save the trouble.

### Quick Start

#### Prerequisites

- **jq** is required to parse JSON configuration. Reference [Here](https://stedolan.github.io/jq/).

    ```shell
    # For Debian based distros like Ubuntu
    $ sudo apt-get install jq git curl zsh
    # For RHEL based distros 
    $ sudo dnf install jq git curl zsh
    # For macOS
    $ brew install jq git curl
    ```

#### Setup

1. **Basic Setup:**

- Create necessary directories:
  ```bash
  mkdir -p data/github log temp
  ```

- If using default storage paths, prepare directories:
  ```bash
  sudo mkdir -p /opt/git/{git-repo,git-release,git-tag}
  sudo chown -R $USER:$USER /opt/git
  ```

2. **Configuration:**

- Copy the example configuration:
  ```bash
  cp template/repo-example.json data/repo.json
  ```

- Edit `data/repo.json` with your repositories (see [Configuration Format](#configuration-format) below)

3. **GitHub Access Token (Recommended):**

- Generate a token at GitHub Settings → Developer settings → Personal access tokens
- Save it:
  ```bash
  echo "your_github_token_here" > data/github/github-access-token
  chmod 600 data/github/github-access-token
  ```

#### Usage

**Run the synchronization:**
```shell
$ ./sync-tool.sh
```

**Preview operations without executing:**
```shell
$ ./sync-tool.sh --dry-run
```

**Use custom configuration files:**
```shell
$ ./sync-tool.sh -f /path/to/config.json -d /path/to/repo.json
```

**Setup automated daily sync with cron:**
```shell
# Edit crontab
$ crontab -e

# Add line to run at 2:00 AM daily
0 2 * * * cd /path/to/git-mirror-synchronizer && ./sync-tool.sh 2>&1 | tee -a ~/.git-mirror-sync/git-mirror-sync.log
```

### Configuration Format

The tool uses a three-tier configuration system:

```
repo.json (per-repo) > data/config.json (custom global) > config/config.global.json (default global)
```

**Repository Configuration (`data/repo.json`):**

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

**Key Fields:**

- **repoUrl** (required): Upstream repository URL
- **identifier** (optional): Custom identifier (default: extracted from repoUrl)
- **catalog** (optional): Category path for organization (e.g., "tools/automation")
- **repo.sync**: Enable repository sync ("true"/"false")
- **release.download**: Enable release downloads ("true"/"false")
- **release.excludeKeywords**: Comma-separated keywords to exclude from downloads
- **tag.download**: Enable tag downloads ("true"/"false")
- **mirror**: Array of mirror destinations

**Global Configuration (`data/config.json` - optional):**

```json
{
  "repo": {
    "storagePath": "/custom/path/repos",
    "sync": "true"
  },
  "release": {
    "storagePath": "/custom/path/releases",
    "download": "false"
  }
}
```

### Command Line Options

| Option | Description |
|--------|-------------|
| `-f, --config-file FILE` | Specify custom global configuration file |
| `-d, --data-file FILE` | Specify repository data file |
| `--dry-run` | Preview operations without executing |
| `-h, --help, help` | Display help manual |

### Directory Structure

**Project Structure:**
```
git-mirror-synchronizer/
├── sync-tool.sh          # Main executable
├── MANUAL.md             # Comprehensive documentation
├── component/            # Core components
│   ├── common.sh         # Common utilities
│   ├── environment.sh    # Environment variables
│   └── operation.sh      # Core operations
├── config/               # Configuration files
│   └── config.global.json
├── data/                 # User data (gitignored)
│   ├── config.json       # Optional custom global config
│   ├── repo.json         # Repository list
│   └── github/
│       └── github-access-token
├── module/               # Platform-specific modules
│   ├── module-github.sh
│   ├── module-gitlab.sh
│   └── module-gitee.sh
└── template/             # Configuration examples
    └── repo-example.json
```

**Storage Structure (default):**
```
/opt/git/
├── git-repo/             # Cloned repositories
│   └── {catalog}/
│       └── {identifier}/
├── git-release/          # Release artifacts
│   └── {identifier}/
│       └── {version}/
└── git-tag/              # Tag archives
    └── {identifier}/
        └── {tag}/
```

### Examples

**Example 1: Basic Repository Sync**
```json
[
  {
    "repoUrl": "https://github.com/torvalds/linux.git",
    "catalog": "kernel",
    "mirror": [
      {
        "name": "backup",
        "repoUrl": "git@gitserver.local:backup/linux.git"
      }
    ]
  }
]
```

**Example 2: Download Releases Only**
```json
[
  {
    "repoUrl": "https://github.com/kubernetes/kubernetes.git",
    "catalog": "cloud",
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

**Example 3: Multiple Mirrors**
```json
[
  {
    "repoUrl": "https://github.com/user/important-project.git",
    "catalog": "projects",
    "mirror": [
      {
        "name": "gitlab",
        "repoUrl": "git@gitlab.com:backup/important-project.git"
      },
      {
        "name": "gitea",
        "repoUrl": "git@gitea.local:backup/important-project.git"
      }
    ]
  }
]
```

### Troubleshooting

**Common Issues:**

1. **Config file not found**: Ensure `data/repo.json` exists
2. **GitHub API rate limit**: Add GitHub access token at `data/github/github-access-token`
3. **Permission denied**: Check write permissions for storage paths
4. **Mirror push failed**: Verify SSH keys and remote access

See [MANUAL.md](MANUAL.md) for detailed troubleshooting guide.

### Features

- ✅ Multi-repository management
- ✅ Multiple mirror destinations per repository
- ✅ GitHub release and tag downloads
- ✅ Flexible configuration hierarchy with inheritance
- ✅ Dry-run mode for testing
- ✅ Cross-platform (Linux and macOS)
- ✅ Automated scheduling via cron
- ✅ Selective sync and download per repository
- ✅ Release asset filtering by keywords

### Documentation

- **[MANUAL.md](MANUAL.md)** - Complete usage manual with examples and troubleshooting
- **[template/repo-example.json](template/repo-example.json)** - Configuration example
- **[config/config.global.json](config/config.global.json)** - Global defaults

### License

This project is licensed under the MIT License. See [LICENSE](LICENSE) file for details.
