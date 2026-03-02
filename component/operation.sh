#!/usr/bin/env zsh

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

  # TODO consider unify FILE and PATH variable naming, e.g. REPORT_FILE_PATH or REPORT_FILE
  # TODO consider put all predifined file path variables into a single function to avoid confusion
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

