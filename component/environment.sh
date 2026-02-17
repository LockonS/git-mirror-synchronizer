#!/usr/bin/env zsh

export DOWNLOAD_RETRY=3
export DOWNLOAD_RETRY_DELAY=2

export GLOBAL_CONFIG_FILE="$CONFIG_PATH/config.global.json"
export DEFAULT_CONFIG_FILE="$DATA_PATH/config.json"
export DEFAULT_DATA_FILE="$DATA_PATH/repo.json"

export OPERATION_TIME=$(date '+%Y-%m-%d %H:%M:%S')
export DRY_RUN="false"

export DEFAULT_REPO_STORAGE_PATH="/opt/git/git-repo"
export DEFAULT_TAG_STORAGE_PATH="/opt/git/git-tag"
export DEFAULT_RELEASE_STORAGE_PATH="/opt/git/git-release"
