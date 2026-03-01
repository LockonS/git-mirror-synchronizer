#!/usr/bin/env zsh

op_prompt_checkpoint() {
  local MSG NEWLINE_BEFORE ARROW_COLOR
  ARROW_COLOR="$BLUE"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n) NEWLINE_BEFORE="true"; shift ;;
      -c) ARROW_COLOR="$2"; shift 2 ;;
      *) MSG="$1"; shift ;;
    esac
  done

  [[ -n "$NEWLINE_BEFORE" ]] && echo -e ""
  echo -e "${ARROW_COLOR}==>${NC} ${WHITE}${MSG}${NC}"
}

op_prompt_debug() {
  if [[ "$LOG_LEVEL" != "debug" ]]; then
    return 0
  fi
  echo -e "${GREY}${1}${NC}"
}

op_prompt_info() {
  echo -e "${WHITE}${1}${NC}"
}

op_prompt_warn() {
  echo -e "${BOLD}${YELLOW}${1}${NC}"
}

op_prompt_error() {
  echo -e "${BOLD}${RED}${1}${NC}"
}

op_run_cmd() {
  local CMD_STR="${*}"

  if [[ "$DRY_RUN" != true ]]; then
    if ! zsh -c "$CMD_STR"; then
      op_prompt_error "Error: command execute failure"
      return 1
    fi
  else
    # print command on console
    echo -e "\n${GREY}${CMD_STR}${NC}\n"
  fi
}

# run a command and track its failure into the global REPO_PROCESS_STATUS
op_run_tracked_cmd() {
  if ! op_run_cmd "$@"; then
    REPO_PROCESS_STATUS="failed"
  fi
}

op_run_cmd_with_result() {
  local CMD_STR="${*}"

  if [[ "$DRY_RUN" != true ]]; then
    CMD_EXEC_STDOUT=$(zsh -c "$CMD_STR")
  else
    # print command on console
    echo -e "\n${GREY}${CMD_STR}${NC}\n"
  fi
}

op_get_os_type() {
  local OSNAME
  OSNAME=$(uname -s | tr "[:lower:]" "[:upper:]")
  if [[ $OSNAME == DARWIN* ]]; then
    export OS_TYPE="MACOS"
  elif [[ $OSNAME == LINUX* ]]; then
    export OS_TYPE="LINUX"
  else
    echo "Unsupported OS, exiting"
    exit 1
  fi
}


# load setting from global config file and in-line parameter
op_load_runtime_config() {
  local RUNTIME_CONFIG_FILE GLOBAL_RUNTIME_CONFIG
  RUNTIME_CONFIG_FILE="${1}"
  GLOBAL_RUNTIME_CONFIG=$(jq -s '.[0] * .[1]' "$GLOBAL_CONFIG_FILE" "$RUNTIME_CONFIG_FILE")

  if [[ "$LOG_LEVEL" == "debug" ]]; then
    op_prompt_debug "Loading runtime config: '${YELLOW}${RUNTIME_CONFIG_FILE}${NC}'"
  fi

  echo "$GLOBAL_RUNTIME_CONFIG" >"${TEMP_PATH}/global.temp.json"
}

op_initialization() {
  echo -e "\n--------------------- $OPERATION_TIME ---------------------\n"
  mkdir -p "$TEMP_PATH"
  mkdir -p "$LOG_PATH"
  mkdir -p "$REPORT_PATH"

  LOG_DATE=$(date '+%Y%m%d')
  LOG_TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
  LOG_FILE="$LOG_PATH/${LOG_TIMESTAMP}.log"
  touch "$LOG_FILE"

  REPORT_FILE="$REPORT_PATH/$LOG_DATE/${LOG_TIMESTAMP}.txt"
  HTML_BRIEF_REPORT_FILE="$REPORT_PATH/$LOG_DATE/brief-report-${LOG_TIMESTAMP}.html"
  HTML_FULL_REPORT_FILE="$REPORT_PATH/$LOG_DATE/full-report-${LOG_TIMESTAMP}.html"
  
  mkdir -p "$(dirname "$REPORT_FILE")"
  touch "$REPORT_FILE"

  export LOG_FILE REPORT_FILE HTML_BRIEF_REPORT_FILE HTML_FULL_REPORT_FILE

  if [[ ! -f "$DEFAULT_CONFIG_FILE" ]]; then
    op_prompt_checkpoint "Default config file not found, creating from global config template" 
    op_prompt_debug "Global config file: ${GREEN}${GLOBAL_CONFIG_FILE}${NC}"
    cp "$GLOBAL_CONFIG_FILE" "$DEFAULT_CONFIG_FILE"
  fi
}

# apply execution mode to override global configuration
op_apply_execution_mode() {
  local EXECUTION_MODE="${1}"
  local MODIFIED_CONFIG
  
  case "$EXECUTION_MODE" in
    'all')
      # no changes needed, use original config
      op_prompt_debug "Execution mode: all (sync, release, tag)"
      ;;
    'update')
      # only update repos, no mirror sync, no downloads
      op_prompt_checkpoint "Execution mode: ${BOLD}${GREEN}update${NC} (clone/pull repos only)"
      MODIFIED_CONFIG=$(cat "${TEMP_PATH}/global.temp.json" | jq '.repo.sync = "true" | .release.download = "false" | .tag.download = "false"')
      echo "$MODIFIED_CONFIG" >"${TEMP_PATH}/global.temp.json"
      # enable repo sync but skip mirror operations
      export SKIP_MIRROR_SYNC="true"
      ;;
    'sync')
      # update repos and sync to mirrors, no downloads
      op_prompt_checkpoint "Execution mode: ${BOLD}${GREEN}sync${NC} (clone/pull and sync to mirrors)"
      MODIFIED_CONFIG=$(cat "${TEMP_PATH}/global.temp.json" | jq '.repo.sync = "true" | .release.download = "false" | .tag.download = "false"')
      echo "$MODIFIED_CONFIG" >"${TEMP_PATH}/global.temp.json"
      ;;
    'release')
      # only download releases
      op_prompt_checkpoint "Execution mode: ${BOLD}${GREEN}release${NC} (download releases only)"
      MODIFIED_CONFIG=$(cat "${TEMP_PATH}/global.temp.json" | jq '.repo.sync = "false" | .release.download = "true" | .tag.download = "false"')
      echo "$MODIFIED_CONFIG" >"${TEMP_PATH}/global.temp.json"
      ;;
    'tag')
      # only download tags
      op_prompt_checkpoint "Execution mode: ${BOLD}${GREEN}tag${NC} (download tags only)"
      MODIFIED_CONFIG=$(cat "${TEMP_PATH}/global.temp.json" | jq '.repo.sync = "false" | .release.download = "false" | .tag.download = "true"')
      echo "$MODIFIED_CONFIG" >"${TEMP_PATH}/global.temp.json"
      ;;
  esac
}

