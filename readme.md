## Git Mirror Synchronizer

A shell script that automates tracking upstream repositories and syncing them to mirror destinations — clone, update,
push, and optionally download GitHub releases and tags.

> **Scenario**  
> I've got a self-hosted git server and need to back up repositories from GitHub (or other sources) while keeping them up-to-date
> automatically. A simple shell script triggered by crontab does the job. As the tracking list grows, this script keeps
> everything neat and organized.

📖 **[Complete Usage Manual](MANUAL.md)** — detailed reference, advanced configuration, and troubleshooting

---

### Prerequisites

**jq** is required to parse JSON configuration.

```shell
# Debian / Ubuntu
sudo apt-get install jq git curl zsh
# RHEL / Fedora
sudo dnf install jq git curl zsh
# macOS
brew install jq git curl
```

---

### Quick Start

#### 1. Prepare directories

```bash
mkdir -p data/github temp-files
# example directory on Linux; adjust as needed
sudo mkdir -p /opt/git/{git-repo,git-release,git-tag}
sudo chown -R $USER:$USER /opt/git
```

#### 2. Create a minimal repository list

Create `data/repo.json` with the single required field — `repoUrl`:

```json
[
  {
    "repoUrl": "https://github.com/user/repository.git"
  }
]
```

That's enough to clone and locally mirror the repository using the default settings defined in
`config/config.global.json`.

#### 3. Run

```bash
./sync-tool.sh
```

Preview what would happen without making any changes:

```bash
./sync-tool.sh --dry-run
```

---

### Configuration

The tool resolves each setting through a three-tier hierarchy — per-repo values override global custom values, which
override the built-in defaults:

```
data/repo.json  (per-repo)
  └─▶  data/config.json  (optional custom global)
         └─▶  config/config.global.json  (built-in defaults)
```

#### Built-in defaults (`config/config.global.json`)

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
  "report": {
    "s3": {
      "enable": "false",
      "profile": "",
      "bucket": "",
      "pathPrefix": "",
      "urlPrefix": ""
    }
  },
  "notification": {
    "email": {
      "enable": "false",
      "sender": "",
      "receiver": ""
    }
  }
}
```

#### Per-repo configuration (`data/repo.json`)

Below is a fully annotated entry. Every field except `repoUrl` is optional.

```javascript
[
    {
        "repoUrl": "https://github.com/user/repository.git",    // (required) upstream URL
        "identifier": "user/repository",                        // custom ID used in storage paths (default: derived from repoUrl)
        "catalog": "category/subcategory",                      // sub-folder grouping inside the storage root
        "repo": {
            "storagePath": "/opt/git/git-repo",                   // where bare clones are stored
            "sync": "true"                                        // clone/fetch the repo and push to mirrors
        },
        "release": {
            "storagePath": "/opt/git/git-release",                // where release assets are saved
            "download": "true",                                   // download GitHub release assets
            "keptVersionNum": "3",                                // number of latest releases to keep (older ones are pruned)
            "excludeKeywords": [
                "windows",
                "arm64"
            ],                                                    // skip assets whose filename contains any of these strings
            "keptVersionKeywords": [
                "v1.0"
            ]                                                     // always keep releases matching these strings, regardless of keptVersionNum
        },
        "tag": {
            "storagePath": "/opt/git/git-tag",                    // where tag archives are saved
            "download": "true",                                   // download tag source archives
            "keptVersionNum": "3",                                // number of latest tags to keep
            "keptVersionKeywords": [
                "v1.0"
            ]                                                     // always keep tags matching these strings
        },
        "mirror": [
            {
                "name": "gitlab",                                   // label for logging
                "repoUrl": "git@gitlab.example.com:mirror/repository.git",      // push destination
                "retryForcePush": "false"                                // use --force on push
            }
        ]
    }
]
```

**Field reference:**

| Field                         | Required | Default                | Description                                       |
|-------------------------------|----------|------------------------|---------------------------------------------------|
| `repoUrl`                     | ✅        | —                      | Upstream repository URL                           |
| `identifier`                  | —        | Derived from `repoUrl` | ID used in local storage paths                    |
| `catalog`                     | —        | `""`                   | Sub-folder under `storagePath` for grouping repos |
| `repo.storagePath`            | —        | `/opt/git/git-repo`    | Root directory for bare clones                    |
| `repo.sync`                   | —        | `"true"`               | Enable clone/fetch and mirror push                |
| `release.storagePath`         | —        | `/opt/git/git-release` | Root directory for release asset downloads        |
| `release.download`            | —        | `"true"`               | Enable GitHub release downloads                   |
| `release.keptVersionNum`      | —        | `"5"`                  | How many latest releases to retain                |
| `release.excludeKeywords`     | —        | `[]`                   | Skip assets whose filename contains any keyword   |
| `release.keptVersionKeywords` | —        | `[]`                   | Releases pinned regardless of `keptVersionNum`    |
| `tag.storagePath`             | —        | `/opt/git/git-tag`     | Root directory for tag archive downloads          |
| `tag.download`                | —        | `"true"`               | Enable tag archive downloads                      |
| `tag.keptVersionNum`          | —        | `"5"`                  | How many latest tag archives to retain            |
| `tag.keptVersionKeywords`     | —        | `[]`                   | Tags pinned regardless of `keptVersionNum`        |
| `mirror[].name`               | —        | —                      | Label for the mirror (used in logs)               |
| `mirror[].repoUrl`            | —        | —                      | Push destination URL                              |
| `mirror[].retryForcePush`          | —        | `"false"`              | Pass `--force` when pushing                       |
| `notification.email.enable`   | —        | `"false"`              | Enable email notifications (`"true"`/`"false"`)   |
| `notification.email.sender`   | —        | `""`                   | Sender address (defaults to `noreply@git-mirror-synchronizer`) |
| `notification.email.receiver` | —        | `""`                   | Recipient address for sync result notifications   |

#### Custom global config (`data/config.json`) — optional

Override defaults for all repositories without touching individual entries:

```json
{
  "repo": {
    "storagePath": "/custom/path/repos",
    "sync": "true"
  },
  "release": {
    "storagePath": "/custom/path/releases",
    "download": "false"
  },
  "notification": {
    "email": {
      "enable": "true",
      "sender": "noreply@example.com",
      "receiver": "admin@example.com"
    }
  }
}
```

#### GitHub access token (recommended)

Required for private repositories and avoids API rate limits when downloading releases/tags.

```bash
echo "your_github_token_here" > data/github/github-access-token
chmod 600 data/github/github-access-token
```

---

### Examples

**Minimal — just sync a repo locally:**

```json
[
  {
    "repoUrl": "https://github.com/torvalds/linux.git"
  }
]
```

**Sync and push to a mirror:**

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

**Download releases only (no repo sync):**

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
      "excludeKeywords": [
        "darwin",
        "windows"
      ]
    }
  }
]
```

**Multiple mirrors:**

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

---

### Command Line Options

| Option                    | Description                                               |
|---------------------------|-----------------------------------------------------------|
| `-f, --config-file FILE`  | Custom global configuration file                          |
| `-d, --data-file FILE`    | Repository data file                                      |
| `-r, --repo-url URL`      | Filter by repoUrl; repeatable (`-r url1 -r url2`) or comma-separated (`-r url1,url2`). Also matches `url.git` if no `.git` suffix is given. |
| `-s, --start-index INDEX` | Start from repository index (0-based)                     |
| `-e, --end-index INDEX`   | Stop before repository index (0-based)                    |
| `-m, --mode MODE`         | Execution mode: `all`, `update`, `sync`, `release`, `tag` |
| `--continue`              | Resume from last saved progress                           |
| `--retry`                    | Retry failed repos listed in `temp-files/failed-repo.txt` from the last run |
| `--dry-run`               | Preview operations without executing                      |
| `-h, --help`              | Display help manual                                       |

---

### Automation

Run at 2:00 AM daily with cron:

```shell
crontab -e
# add:
0 2 * * * cd /path/to/git-mirror-synchronizer && ./sync-tool.sh 2>&1 | tee -a ~/.git-mirror-sync/sync.log
```

---

### Directory Structure

```
git-mirror-synchronizer/
├── sync-tool.sh       # main script
├── component/         # core logic (common, environment, operation)
├── config/            # built-in defaults
├── data/              # your config and credentials (gitignored)
│   ├── repo.json      # repository list
│   ├── config.json    # optional global overrides
│   └── github/github-access-token
├── platform/          # platform modules (github, gitlab, general)
├── template/          # example configuration
└── temp-files/        # runtime files (logs, reports, progress) — auto-created

/opt/git/              # default storage root
├── git-repo/{catalog}/{identifier}/   # bare clones
├── git-release/{catalog}/{identifier}/{version}/
└── git-tag/{catalog}/{identifier}/{tag}/
```

---

### Features

- ✅ Multi-repository management
- ✅ Multiple mirror destinations per repository
- ✅ GitHub release and tag downloads with keyword filtering
- ✅ Three-tier configuration hierarchy with per-repo overrides
- ✅ Email notifications on sync completion
- ✅ S3 HTML report upload via rclone
- ✅ Dry-run mode
- ✅ Cross-platform (Linux and macOS)
- ✅ Cron-friendly with progress resume (`--continue`) and failed-repo retry (`--retry`)

---

### License

MIT — see [LICENSE](LICENSE) for details.
