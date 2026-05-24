#!/usr/bin/env zsh

SYNC_TOOL_PATH=$(dirname "$(readlink -f "$0")")
export SYNC_TOOL_PATH

# resource path
export COMPONENT_PATH="$SYNC_TOOL_PATH/component"
export PLATFORM_MODULE_PATH="$SYNC_TOOL_PATH/platform"
export DATA_PATH="$SYNC_TOOL_PATH/data"
export CONFIG_PATH="$SYNC_TOOL_PATH/config"
export TEMP_PATH="$SYNC_TOOL_PATH/temp-files"
export LOG_PATH="$TEMP_PATH/log"
export REPORT_PATH="$TEMP_PATH/report"
export FAILED_REPO_FILE="$TEMP_PATH/failed-repo.txt"
export PROGRESS_INDEX_FILE="$TEMP_PATH/progress-index"

# include component
source "$COMPONENT_PATH/common.sh"
source "$COMPONENT_PATH/environment.sh"
source "$COMPONENT_PATH/util.sh"
source "$COMPONENT_PATH/operation.sh"
source "$COMPONENT_PATH/git.sh"
source "$COMPONENT_PATH/report.sh"
source "$COMPONENT_PATH/mail.sh"

# include module
source "$PLATFORM_MODULE_PATH/module-github.sh"
source "$PLATFORM_MODULE_PATH/module-gitlab.sh"
source "$PLATFORM_MODULE_PATH/module-general.sh"

# function manual
sync_tool_manual() {
  echo "usage: mirror-sync.sh "
  echo "       -h,--help,help             Show manual page"
  echo "       -f,--config-file file      Specify input config file, default to path-to-script/data/config.json"
  echo "       -d,--data-file   file      Specify input data file, default to path-to-script/data/repo.json"
  echo "       -r,--repo-url    url       Filter by repoUrl; repeatable (-r url1 -r url2) or comma-separated (-r url1,url2)"
  echo "                                  If url does not end with .git, also matches url.git"
  echo "       -s,--start-index index     Start processing from repository index (0-based)"
  echo "       -e,--end-index   index     Stop processing before repository index (0-based)"
  echo "       -m,--mode        mode      Optional, default to all. [all| update| sync | release | tag]"
  echo "       --continue                 Resume from the last saved progress index"
  echo "       --retry                    Retry failed repos from the last run report"
  echo "       --dry-run                  Enable dry run mode (no actual changes)"
}

# shellcheck disable=SC2034
sync_tool_entry() {
  local RUNTIME_CONFIG_FILE="$DEFAULT_CONFIG_FILE"
  local RUNTIME_DATA_FILE="$DEFAULT_DATA_FILE"
  local EXECUTION_MODE="all"
  local CONTINUE_MODE="false"
  local RETRY_MODE="false"
  local DRY_RUN="false"
  local FILTER_REPO_URLS=()
  local START_INDEX=""
  local END_INDEX=""
  
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
        FILTER_REPO_URLS+=("${2}")
        shift
        shift
        ;;
      '-s' | '--start-index')
        START_INDEX=${2}
        shift
        shift
        ;;
      '-e' | '--end-index')
        END_INDEX=${2}
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
      '--retry')
        RETRY_MODE="true"
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
      echo -e "${RED}Invalid execution mode: ${EXECUTION_MODE}${NC}"
      echo "Valid modes: all, update, sync, release, tag"
      return 1
      ;;
  esac

  # validate input START_INDEX
  if [[ -n "$START_INDEX" ]]; then
    # Remove all digits - if result is non-empty, it contains non-digit characters
    if [[ -n "${START_INDEX//[0-9]/}" ]]; then
      op_prompt_error "Invalid START_INDEX: ${START_INDEX}, must be a non-negative integer (>= 0)"
      return 1
    fi
  fi

  # validate input END_INDEX
  if [[ -n "$END_INDEX" ]]; then
    # Remove all digits - if result is non-empty, it contains non-digit characters
    if [[ -n "${END_INDEX//[0-9]/}" ]]; then
      op_prompt_error "Invalid END_INDEX: ${END_INDEX}, must be a non-negative integer (>= 0)"
      return 1
    fi
  fi

  # check if config file exist
  [[ ! -f $RUNTIME_CONFIG_FILE ]] && echo "Config file '${YELLOW}${RUNTIME_CONFIG_FILE}${NC}' does not exist" && return 1
  [[ ! -f $RUNTIME_DATA_FILE ]] && echo "Data file '${YELLOW}${RUNTIME_DATA_FILE}${NC}' does not exist" && return 1

  # load runtime config
  op_load_runtime_config "$RUNTIME_CONFIG_FILE"

  # apply execution mode overrides
  op_apply_execution_mode "$EXECUTION_MODE"

  # load runtime data
  local RUNTIME_REPO_DATA_CONTENT REPO_LENGTH REPO_INDEX REPO_DATA PROGRESS_INDEX REPO_MATCHED
  RUNTIME_REPO_DATA_CONTENT=$(cat "$RUNTIME_DATA_FILE")
  REPO_LENGTH=$(echo "$RUNTIME_REPO_DATA_CONTENT" | jq '. | length')
  REPO_MATCHED="false"

  # if running in retry mode
  if [[ "$RETRY_MODE" == "true" ]]; then
    if [[ -f "$FAILED_REPO_FILE" && -s "$FAILED_REPO_FILE" ]]; then
      op_prompt_checkpoint -n "Loading failed repos from: ${BOLD}${FAILED_REPO_FILE}${NC}"
      while IFS= read -r FAIL_REPO_URL; do
        [[ -n "$FAIL_REPO_URL" ]] && FILTER_REPO_URLS+=("$FAIL_REPO_URL")
      done < "$FAILED_REPO_FILE"
      op_prompt_info "Retrying ${BOLD}${#FILTER_REPO_URLS[@]}${NC} failed repo(s) from last run"
    else
      op_prompt_debug "No failed repos file found or it is empty: ${BOLD}${FAILED_REPO_FILE}${NC}"
    fi
  fi

  # determine start index
  if [[ "$CONTINUE_MODE" == "true" ]]; then
    if [[ -f "$PROGRESS_INDEX_FILE" ]]; then
      START_INDEX=$(cat "$PROGRESS_INDEX_FILE")
      op_prompt_checkpoint "Resuming from repo ${START_INDEX} of ${REPO_LENGTH}"
    else
      op_prompt_warn "No saved progress found, starting from the beginning"
    fi
  fi

  # report counters
  local REPORT_TOTAL REPORT_SUCCESS REPORT_FAILED REPORT_UPDATED REPORT_REL_DOWNLOADED FAILED_REPO_URLS
  REPORT_TOTAL=0 
  REPORT_SUCCESS=0 
  REPORT_FAILED=0
  REPORT_UPDATED=0 
  REPORT_REL_DOWNLOADED=0
  FAILED_REPO_URLS=()

  # traverse repo list, determine start and end index
  if [[ -z "$START_INDEX" ]]; then
    START_INDEX=0
  fi
  if [[ -z "$END_INDEX" ]]; then
    END_INDEX="$REPO_LENGTH"
  fi

  # write report header
  local FILTER_REPO_URL_DISPLAY="${(j:, :)FILTER_REPO_URLS}"
  op_report_write_header "$EXECUTION_MODE" "$START_INDEX" "$END_INDEX" "$FILTER_REPO_URL_DISPLAY"

  for ((REPO_INDEX = START_INDEX; REPO_INDEX < END_INDEX; REPO_INDEX++)); do
    REPO_DATA=$(echo "$RUNTIME_REPO_DATA_CONTENT" | jq ".[${REPO_INDEX}]")
    PROGRESS_INDEX=$((REPO_INDEX + 1))
    REPO_URL=$(echo "$REPO_DATA" | jq ".repoUrl" | tr -d '"')

    # filter by repoUrl if --repo-url is specified; also match with .git suffix if a filter URL has none
    if [[ ${#FILTER_REPO_URLS[@]} -gt 0 ]]; then
      local MATCHED_FILTER="false"
      for _FILTER_URL in "${FILTER_REPO_URLS[@]}"; do
        if [[ "$REPO_URL" == "$_FILTER_URL" ]] || \
           { [[ "$_FILTER_URL" != *.git ]] && [[ "$REPO_URL" == "${_FILTER_URL}.git" ]]; }; then
          MATCHED_FILTER="true"
          break
        fi
      done
      [[ "$MATCHED_FILTER" != "true" ]] && continue
    fi

    REPO_MATCHED="true"
    [[ ${#FILTER_REPO_URLS[@]} -eq 0 ]] && echo -e "\n--------------------- Progress $PROGRESS_INDEX/$REPO_LENGTH ---------------------\n"

    # dispatch repo data to operation module and get processing result
    op_dispatch_repo_handler "$REPO_DATA"

    # update report counters and write report result for current repo
    REPORT_TOTAL=$((REPORT_TOTAL + 1))
    if [[ "$REPO_PROCESS_STATUS" == "failed" ]]; then
      REPORT_FAILED=$((REPORT_FAILED + 1))
      FAILED_REPO_URLS+=("$REPO_URL")
      op_report_append_repo_result "$PROGRESS_INDEX" "$REPO_LENGTH" "$REPO_URL" "FAIL"
    else
      REPORT_SUCCESS=$((REPORT_SUCCESS + 1))
      op_report_append_repo_result "$PROGRESS_INDEX" "$REPO_LENGTH" "$REPO_URL" "PASS"
    fi

    if [[ "$REPO_UPDATED" == "true" ]]; then
      REPORT_UPDATED=$((REPORT_UPDATED + 1))
    fi

    if [[ -n "$REPO_RELEASE_DL_COUNT" ]] && [[ "$REPO_RELEASE_DL_COUNT" -gt 0 ]]; then
      REPORT_REL_DOWNLOADED=$((REPORT_REL_DOWNLOADED + REPO_RELEASE_DL_COUNT))
    fi

    op_report_append_repo_detail "$REPO_URL" "$REPO_UPDATED" "$REPO_RELEASE_DL_COUNT"

    [[ ${#FILTER_REPO_URLS[@]} -eq 0 ]] && echo "$PROGRESS_INDEX" > "$PROGRESS_INDEX_FILE"
  
  done

  # warn if --repo-url matched nothing
  if [[ ${#FILTER_REPO_URLS[@]} -gt 0 ]] && [[ "$REPO_MATCHED" != "true" ]]; then
    op_prompt_warn "No repository matched repoUrl: ${BOLD}${FILTER_REPO_URL_DISPLAY}${NC}"
  fi

  # clear progress file on successful completion
  [[ -f "$PROGRESS_INDEX_FILE" ]] && rm -f "$PROGRESS_INDEX_FILE"

  # export failed repo URLs to temp-files/failed-repo.txt (clear file if none failed)
  op_export_failed_repos "${FAILED_REPO_URLS[@]}"

  # print and save report summary
  op_report_write_summary "$REPORT_TOTAL" "$REPORT_SUCCESS" "$REPORT_FAILED" "$REPORT_UPDATED" "$REPORT_REL_DOWNLOADED"

  # assemble bucket file path and public URL for the generated report file, export as env variable
  op_generate_report_file_path "$RUNTIME_CONFIG_FILE" "$REPORT_FILE"

  # generate HTML report files
  op_generate_html_report "$EXECUTION_MODE" "$REPORT_TOTAL" "$REPORT_SUCCESS" "$REPORT_FAILED" "$REPORT_FILE" "$REPORT_UPDATED" "$REPORT_REL_DOWNLOADED"

  # upload HTML report
  op_upload_report_s3 "$RUNTIME_CONFIG_FILE" "$HTML_FULL_REPORT_FILE"

  # send email notification with report (skipped when filtering by specific repo URLs)
  if [[ ${#FILTER_REPO_URLS[@]} -eq 0 ]]; then
    op_process_email_notification "$RUNTIME_CONFIG_FILE"
  fi
}

op_initialization

# Pipe all output from sync_tool_entry to both console and log file
sync_tool_entry "$@" 2>&1 | tee -a "$LOG_FILE"

