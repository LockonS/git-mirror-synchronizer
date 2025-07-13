#!/usr/bin/env zsh

SYNC_TOOL_PATH=$(dirname "$(readlink -f "$0")")
export SYNC_TOOL_PATH

# resource path
export COMPONENT_PATH="$SYNC_TOOL_PATH/component"
export DATA_PATH="$SYNC_TOOL_PATH/data"
export LOG_PATH="$SYNC_TOOL_PATH/log"

# include component
source "$COMPONENT_PATH/common.sh"
source "$COMPONENT_PATH/environment.sh"
source "$COMPONENT_PATH/operation.sh"

# function manual
sync_tool_manual() {
  echo "usage: mirror-sync.sh "
  echo "       -h,--help,help             Show manual page"
  echo "       -f,--config-file file      Specify input config file, default to path-to-script/data/repo.json"
  echo "       -m,--mode        mode      Specify execute mode [init | sync | download], default is 'sync' mode"
  echo "       --sync-mirror    boolean   Specify if mirror repo will be synced, default is true"
}

# shellcheck disable=SC2034
sync_tool_entry() {
  local TARGET_CONFIG_FILE="$DEFAULT_CONFIG_FILE"
  local TARGET_DATA_FILE="$DEFAULT_DATA_FILE"
  local TARGET_REPO TARGET_EXEC_MODE

  while [ $# -gt 0 ]; do
    case ${1} in
      '-h' | '--help' | 'help')
        sync_tool_manual
        return 0
        ;;
      '-f' | '--config-file')
        TARGET_CONFIG_FILE=${2}
        shift
        shift
        ;;
      '-d' | '--data-file')
        TARGET_DATA_FILE=${2}
        shift
        shift
        ;;
      '-m' | '--mode')
        TARGET_EXEC_MODE=${2}
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
  [[ ! -f $TARGET_CONFIG_FILE ]] && echo "Config file ${YELLOW}${CONFIG_FILE}${NC} does not exist" && return 1
  [[ ! -f $TARGET_DATA_FILE ]] && echo "Data file ${YELLOW}${DATA_FILE}${NC} does not exist" && return 1

  if [[ -z "$TARGET_EXEC_MODE" ]]; then
    op_prompt_error "Error: execution mode could not be empty"
    sync_tool_manual
    exit 1
  fi

  if ! printf "%s\n" "${EXEC_MODE_OPTION[@]}" | grep -qx "$TARGET_EXEC_MODE"; then
    op_prompt_error "Error: execution mode '$TARGET_EXEC_MODE' not exist"
    sync_tool_manual
    exit 1
  fi

  local REPO_CONFIGURATION REPO_LENGTH REPO_INDEX REPO_DATA PROGRESS_INDEX
  # get config file content
  REPO_CONFIGURATION=$(cat "$CONFIG_FILE")
  # traverse repo list
  REPO_LENGTH=$(echo "$REPO_CONFIGURATION" | jq '. | length')
  for ((REPO_INDEX = 0; REPO_INDEX < REPO_LENGTH; REPO_INDEX++)); do
    REPO_DATA=$(echo "$REPO_CONFIGURATION" | jq ".[$REPO_INDEX]")
    PROGRESS_INDEX=$((REPO_INDEX + 1))
    echo -e "\n--------------- Progress $PROGRESS_INDEX/$REPO_LENGTH ---------------\n"
    op_process_git_repo_list "$REPO_DATA" "$EXECUTE_MODE" "$SINGLE_PROJECT"
  done
}

sync_tool_prepare() {
  LOG_FILE='/var/log/mirror-sync.log'
  if [[ ! -f $LOG_FILE ]]; then
    touch $LOG_FILE
  fi
  if [[ -f "$GITHUB_ACCESS_TOKEN_FILE" ]]; then
    GITHUB_ACCESS_TOKEN=$(cat "$GITHUB_ACCESS_TOKEN_FILE")
  fi
  export GITHUB_ACCESS_TOKEN
  echo -e "\n\n--------------- $EXECUTE_TIME ---------------\n"
}

sync_tool_prepare
sync_tool_entry "$@"
