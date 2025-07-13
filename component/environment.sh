#!/usr/bin/env zsh

export EXEC_MODE_OPTION=("sync" "download")
export DOWNLOAD_RETRY=3
export DOWNLOAD_RETRY_DELAY=2

export DEFAULT_CONFIG_FILE="$DATA_PATH/config.json"
export DEFAULT_DATA_FILE="$DATA_PATH/repo.json"


export EXECUTE_TIME=$(date '+%Y-%m-%d %H:%M:%S')
export DRY_RUN="false"
