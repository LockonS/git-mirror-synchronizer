#!/usr/bin/env zsh

export DOWNLOAD_RETRY=3
export DOWNLOAD_RETRY_DELAY=2

export GLOBAL_CONFIG_FILE="$CONFIG_PATH/config.global.json"
export DEFAULT_CONFIG_FILE="$DATA_PATH/config.json"
export DEFAULT_DATA_FILE="$DATA_PATH/repo.json"

export OPERATION_TIME=$(date '+%Y-%m-%d %H:%M:%S')
export DRY_RUN="false"
export LOG_LEVEL="info"
