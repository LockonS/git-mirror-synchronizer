#!/usr/bin/env zsh

export EXEC_MODE_OPTION=("init" "sync" "download")
export DRY_RUN="false"
export SYNC_MIRROR="true"
export EXECUTE_MODE="sync"
export DOWNLOAD_RETRY=3
export DOWNLOAD_RETRY_DELAY=2
export DEFAULT_RELEASE_STORAGE="/opt/git/git-release"
export DEFAULT_REPO_STORAGE="/opt/git/git-repo"
export DEFAULT_CONFIG_FILE="$DATA_PATH/config.json"
export DEFAULT_DATA_FILE="$DATA_PATH/repo.json"

