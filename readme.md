## Git Mirror Synchronizer

- This is a shell script trying to do the repetitive work of tracking a repository and sync it with another repo.
- **Principle**: What this script does is pretty boring. 
    1. It will initialize a local repository first.
    2. Get updates by running `git pull <trace-branch>` 
    3. Push updates to another mirror repository listed configuration, or do nothing if there's no mirror repository to sync.
 
> **Scenario** 
> I've got a self-hosted git server and trying to back up some repositories from GitHub and keep them up-to-date automatically. A simple shell script triggered by crontab is enough to do the job at first. As the tracking list getting longer and I'd like this sync job to be neat and clean so here is this script.
> I would definitely be happy if this script also helps some of the others save the troubles. 

### Setup

#### Mandatory

- If you follow the default setup, make sure `/opt/git/` directory is available.
- Customize the repo config data based on the example.

#### Optional

- The configuration override priority will be

```
repo.json (repo setting) > data/config.json (custom global override) > template/config.json (project default) 
```

- The project default config file is located at `template/config.json`, this defines the default configuration.
- In order to override the default configuration with custom setup, there are two options.
  1. Create `data` folder and create `config.json` file under it.
  2. Place the config file anywhere and pass it with the command-line arguments `-f` or `--config-file`.
- GitHub access token should be placed at `data/github/access-token`, otherwise it's very likely to reach GitHub api rate limit if you have a long list.

- The file tree should look like below.
```
.
├── data
│   ├── config.json
│   └── repo.json
└── template
    └── config.json
```

### ~~Usage (deprecated)~~

- Default config file should be named as `repo.json` and put in `data` folder (already ignored in `.gitignore`). 
    
    ```
    .
    ├── data
    │   ├── repo.json
    │   └── github-access-token
    ├── mirror-sync.sh
    ├── readme.md
    └── template.json
    ```

- Github access token should be put in `github-access-token` file under `data` folder, otherwise it's very likely to reach the api's rate limit.
    
- **Initialize Mode**: If a new git repository or mirror repository is added, run initialize mode to apply the setting. This operation is idempotence and can be run over and over again without messing up existed repository.

    ```shell
    $ ./sync-tool.sh -m init
    ```

- **Synchronize Mode**: Get update from upstream and sync mirror repositories.

    ```shell
    $ ./sync-tool.sh -m sync
    ```

- Setup crontab task with log output and run this script in daily basis.

    ```shell
    # recommended: use default config file
    0 1 * * * path-to-repo/sync-tool.sh | tee -a /var/log/mirror-sync.log
    # specify a config file
    0 1 * * * path-to-repo/sync-tool.sh -f path-to-data/config.global.json | tee -a /var/log/mirror-sync.log
    ```

### Dependency

- `jq` is required to parse json configuration. Reference [Here](https://stedolan.github.io/jq/).

    ```shell
    # For Debian based distros like Ubuntu
    $ sudo apt-get install jq
    # For RHEL based distros 
    $ sudo dnf install jq
    ```
    
### Config Format

- The content of the configuration file is a json array. 

    ```json
    [
        {
        	"repoLocalPath":"<Local path to save the repository>",
        	"trackRemoteRepoName":"<Name of the upstream repo, origin if not altered>",
        	"trackRemoteRepoUrl":"<Url of the upstream repo>",
        	"mirror":[{
        		"repoName":"<Name of the mirror repo>",
        		"repoUrl":"<Url of the mirror repo>"
        	},{
        		"repoName":"<Name of the other mirror repo>",
        		"repoUrl":"<Url of the other mirror repo>"
        	}],
            "downloadRelease": "<Download latetst github release, boolean>",
            "releaseStoragePath": "<Override default storage location for downloaded artifacts>",
            "excludeKeywords": "<Keywords to exclude the artifacts, split with ','>"
        }
    ]
    ```
