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
export REPORT_PATH="$SYNC_TOOL_PATH/report"

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
  echo "       -r,--repo-url    url       Process a single repository by its repoUrl"
  echo "       -m,--mode        mode      Optional, default to all. [all| update| sync | release | tag]"
  echo "       --continue                 Resume from the last saved progress index"
  echo "       --dry-run                  Enable dry run mode (no actual changes)"
}

# shellcheck disable=SC2034
sync_tool_entry() {
  local RUNTIME_CONFIG_FILE="$DEFAULT_CONFIG_FILE"
  local RUNTIME_DATA_FILE="$DEFAULT_DATA_FILE"
  local EXECUTION_MODE="all"
  local CONTINUE_MODE="false"
  local FILTER_REPO_URL=""
  local PROGRESS_INDEX_FILE="$TEMP_PATH/progress-index"

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
      '-r' | '--repo-url')
        FILTER_REPO_URL=${2}
        shift
        shift
        ;;
      '-m' | '--mode')
        EXECUTION_MODE=${2}
        shift
        shift
        ;;
      '--dry-run')
        DRY_RUN="true"
        shift
        ;;
      '--continue')
        CONTINUE_MODE="true"
        shift
        ;;
      *) shift ;;
    esac
  done

  # validate execution mode
  case "$EXECUTION_MODE" in
    'all' | 'update' | 'sync' | 'release' | 'tag')
      # valid mode
      ;;
    *)
      echo "${RED}Invalid execution mode: ${EXECUTION_MODE}${NC}"
      echo "Valid modes: all, update, sync, release, tag"
      return 1
      ;;
  esac

  # check if config file exist
  [[ ! -f $RUNTIME_CONFIG_FILE ]] && echo "Config file '${YELLOW}${RUNTIME_CONFIG_FILE}${NC}' does not exist" && return 1
  [[ ! -f $RUNTIME_DATA_FILE ]] && echo "Data file '${YELLOW}${RUNTIME_DATA_FILE}${NC}' does not exist" && return 1

  # load runtime config
  op_load_runtime_config "$RUNTIME_CONFIG_FILE"

  # apply execution mode overrides
  op_apply_execution_mode "$EXECUTION_MODE"

  # load runtime data
  local RUNTIME_REPO_DATA_CONTENT REPO_LENGTH REPO_INDEX REPO_DATA PROGRESS_INDEX START_INDEX REPO_MATCHED
  RUNTIME_REPO_DATA_CONTENT=$(cat "$RUNTIME_DATA_FILE")
  REPO_LENGTH=$(echo "$RUNTIME_REPO_DATA_CONTENT" | jq '. | length')
  REPO_MATCHED="false"

  # determine start index
  START_INDEX=0
  if [[ "$CONTINUE_MODE" == "true" ]]; then
    if [[ -f "$PROGRESS_INDEX_FILE" ]]; then
      START_INDEX=$(cat "$PROGRESS_INDEX_FILE")
      op_prompt_checkpoint "Resuming from repo ${START_INDEX} of ${REPO_LENGTH}"
    else
      op_prompt_warn "No saved progress found, starting from the beginning"
    fi
  fi

  # report counters
  local REPORT_TOTAL=0 REPORT_SUCCESS=0 REPORT_FAILED=0

  # write report header
  op_report_write_header "$EXECUTION_MODE"

  # traverse repo list
  for ((REPO_INDEX = START_INDEX; REPO_INDEX < REPO_LENGTH; REPO_INDEX++)); do
    REPO_DATA=$(echo "$RUNTIME_REPO_DATA_CONTENT" | jq ".[${REPO_INDEX}]")
    PROGRESS_INDEX=$((REPO_INDEX + 1))
    REPO_URL=$(echo "$REPO_DATA" | jq ".repoUrl" | tr -d '"')

    # filter by repoUrl if --repo-url is specified
    if [[ -n "$FILTER_REPO_URL" ]] && [[ "$REPO_URL" != "$FILTER_REPO_URL" ]]; then
      continue
    fi

    REPO_MATCHED="true"
    [[ -z "$FILTER_REPO_URL" ]] && echo -e "\n--------------------- Progress $PROGRESS_INDEX/$REPO_LENGTH ---------------------\n"

    op_handle_repo_data "$REPO_DATA"

    REPORT_TOTAL=$((REPORT_TOTAL + 1))
    if [[ "$REPO_PROCESS_STATUS" == "failed" ]]; then
      REPORT_FAILED=$((REPORT_FAILED + 1))
      op_report_repo_result "$PROGRESS_INDEX" "$REPO_LENGTH" "$REPO_URL" "FAIL"
    else
      REPORT_SUCCESS=$((REPORT_SUCCESS + 1))
      op_report_repo_result "$PROGRESS_INDEX" "$REPO_LENGTH" "$REPO_URL" "PASS"
    fi

    [[ -z "$FILTER_REPO_URL" ]] && echo "$PROGRESS_INDEX" > "$PROGRESS_INDEX_FILE"
  
  done

  # warn if --repo-url matched nothing
  if [[ -n "$FILTER_REPO_URL" ]] && [[ "$REPO_MATCHED" != "true" ]]; then
    op_prompt_warn "No repository matched repoUrl: ${FILTER_REPO_URL}"
  fi

  # print and save report summary
  op_report_summary "$REPORT_TOTAL" "$REPORT_SUCCESS" "$REPORT_FAILED"

  # clear progress file on successful completion
  [[ -f "$PROGRESS_INDEX_FILE" ]] && rm -f "$PROGRESS_INDEX_FILE"
}

op_runtime_prepare

# Pipe all output from sync_tool_entry to both console and log file
sync_tool_entry "$@" 2>&1 | tee -a "$LOG_FILE"
