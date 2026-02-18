#!/usr/bin/env zsh

SYNC_TOOL_PATH=$(dirname "$(readlink -f "$0")")
export SYNC_TOOL_PATH

# resource path
export COMPONENT_PATH="$SYNC_TOOL_PATH/component"
export MODULE_PATH="$SYNC_TOOL_PATH/module"
export DATA_PATH="$SYNC_TOOL_PATH/data"
export CONFIG_PATH="$SYNC_TOOL_PATH/config"
export TEMP_PATH="$SYNC_TOOL_PATH/temp"
export LOG_PATH="$SYNC_TOOL_PATH/log"

# include component
source "$COMPONENT_PATH/common.sh"
source "$COMPONENT_PATH/environment.sh"
source "$COMPONENT_PATH/operation.sh"

# include module
source "$MODULE_PATH/module-github.sh"
source "$MODULE_PATH/module-gitlab.sh"
source "$MODULE_PATH/module-gitee.sh"

# function manual
sync_tool_manual() {
  echo "usage: mirror-sync.sh "
  echo "       -h,--help,help             Show manual page"
  echo "       -f,--config-file file      Specify input config file, default to path-to-script/data/config.json"
  echo "       -d,--data-file   file      Specify input data file, default to path-to-script/data/repo.json"
  echo "       --dry-run                  Enable dry run mode (no actual changes)"
}

# shellcheck disable=SC2034
sync_tool_entry() {
  local RUNTIME_CONFIG_FILE="$DEFAULT_CONFIG_FILE"
  local RUNTIME_DATA_FILE="$DEFAULT_DATA_FILE"

  while [ $# -gt 0 ]; do
    case ${1} in
      '-h' | '--help' | 'help')
        sync_tool_manual
        return 0
        ;;
      '-f' | '--config-file')
        RUNTIME_CONFIG_FILE=${2}
        shift
        shift
        ;;
      '-d' | '--data-file')
        RUNTIME_DATA_FILE=${2}
        shift
        shift
        ;;
      '--dry-run')
        DRY_RUN="true"
        shift
        ;;
      *) shift ;;
    esac
  done

  # check if config file exist
  [[ ! -f $RUNTIME_CONFIG_FILE ]] && echo "Config file '${YELLOW}${RUNTIME_CONFIG_FILE}${NC}' does not exist" && return 1
  [[ ! -f $RUNTIME_DATA_FILE ]] && echo "Data file '${YELLOW}${RUNTIME_DATA_FILE}${NC}' does not exist" && return 1

  # load runtime config
  op_load_runtime_config "$RUNTIME_CONFIG_FILE"

  # load runtime data
  local RUNTIME_REPO_DATA_CONTENT REPO_LENGTH REPO_INDEX REPO_DATA PROGRESS_INDEX
  RUNTIME_REPO_DATA_CONTENT=$(cat "$RUNTIME_DATA_FILE")

  # traverse repo list
  REPO_LENGTH=$(echo "$RUNTIME_REPO_DATA_CONTENT" | jq '. | length')
  for ((REPO_INDEX = 0; REPO_INDEX < REPO_LENGTH; REPO_INDEX++)); do
    REPO_DATA=$(echo "$RUNTIME_REPO_DATA_CONTENT" | jq ".[$REPO_INDEX]")
    PROGRESS_INDEX=$((REPO_INDEX + 1))
    echo -e "\n--------------------- Progress $PROGRESS_INDEX/$REPO_LENGTH ---------------------\n"
    op_handle_repo_data "$REPO_DATA"
  done
}

op_runtime_prepare
sync_tool_entry "$@"
