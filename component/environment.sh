#!/usr/bin/env zsh

export EXEC_MODE_OPTION=("sync" "download")
export DRY_RUN="false"

export DOWNLOAD_RETRY=3
export DOWNLOAD_RETRY_DELAY=2

export DEFAULT_CONFIG_FILE="$DATA_PATH/config.json"
export DEFAULT_DATA_FILE="$DATA_PATH/repo.json"
