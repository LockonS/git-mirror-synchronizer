#!/usr/bin/env zsh

# Git operations for git-mirror-synchronizer
# Handles repository cloning, pulling, syncing to mirror remotes, and reporting

# append a single repo result line to the report file
op_report_repo_result() {
  local INDEX="${1}"
  local TOTAL="${2}"
  local REPO_URL="${3}"
  local STATUS="${4}"
  if [[ "$STATUS" == "PASS" ]]; then
    echo -e "[${INDEX}/${TOTAL}] ${GREEN}${BOLD}${STATUS}${NC}   ${REPO_URL}"
  else
    echo -e "[${INDEX}/${TOTAL}] ${RED}${BOLD}${STATUS}${NC}   ${REPO_URL}"
  fi
  [[ -z "$REPORT_FILE" ]] && return 0
  if [[ "$STATUS" == "PASS" ]]; then
    printf "[%d/%d] ${GREEN}${BOLD}%-6s${NC} %s\n" "$INDEX" "$TOTAL" "$STATUS" "$REPO_URL" >> "$REPORT_FILE"
  else
    printf "[%d/%d] ${RED}${BOLD}%-6s${NC} %s\n" "$INDEX" "$TOTAL" "$STATUS" "$REPO_URL" >> "$REPORT_FILE"
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

# write the report file header
op_report_write_header() {
  local EXECUTION_MODE="${1:-all}"
  local START_INDEX="${2:-0}"
  local END_INDEX="${3:-}"
  local FILTER_REPO_URL="${4:-}"
  echo -e "\n${BOLD}${WHITE}=== Sync Report ===${NC}"
  echo -e "Date:    ${CYAN}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
  echo -e "Mode:    ${CYAN}${EXECUTION_MODE}${NC}"
  [[ -z "$FILTER_REPO_URL" ]] && echo -e "Range:   ${CYAN}${START_INDEX} - ${END_INDEX}${NC}"
  [[ -n "$FILTER_REPO_URL" ]] && echo -e "Repo:    ${CYAN}${FILTER_REPO_URL}${NC}"
  [[ -z "$REPORT_FILE" ]] && return 0
  {
    echo -e "${BOLD}${WHITE}=== Sync Report ===${NC}"
    echo -e "Date:    ${CYAN}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "Mode:    ${CYAN}${EXECUTION_MODE}${NC}"
    [[ -z "$FILTER_REPO_URL" ]] && echo -e "Range:   ${CYAN}${START_INDEX} - ${END_INDEX}${NC}"
    [[ -n "$FILTER_REPO_URL" ]] && echo -e "Repo:    ${CYAN}${FILTER_REPO_URL}${NC}"
    echo ""
  } > "$REPORT_FILE"
}

# append summary block to the report file and echo it to stdout
op_report_summary() {
  local TOTAL="${1}"
  local SUCCESS="${2}"
  local FAILED="${3}"

  op_prompt_checkpoint -n "Report task summary"
  op_prompt_info "Total:    ${WHITE}${TOTAL}${NC}"
  op_prompt_info "Success:  ${GREEN}${SUCCESS}${NC}"
  op_prompt_info "Failed:   ${RED}${FAILED}${NC}"

  if [[ -n "$REPORT_FILE" ]]; then
    {
      echo ""
      echo -e "${BOLD}${WHITE}=== Task Summary ===${NC}"
      echo -e "Total:    ${WHITE}${TOTAL}${NC}"
      echo -e "Success:  ${GREEN}${SUCCESS}${NC}"
      echo -e "Failed:   ${RED}${FAILED}${NC}"
    } >> "$REPORT_FILE"

    op_prompt_checkpoint -n "Save task report"
    op_prompt_info "Report file: ${BOLD}${REPORT_FILE}${NC}"
  fi
}

# shellcheck disable=SC2124
# setup repo sync setting and sync repo to local storage, then optionally sync to mirror repos if configured
op_sync_repo() {
  local REPO_RUNTIME_CONFIG REPO_NAME REPO_IDENTIFIER REPO_CATALOG REPO_STORAGE_PATH REPO_LOCAL_PATH
  REPO_RUNTIME_CONFIG="$@"
  REPO_URL=$(echo "$REPO_RUNTIME_CONFIG" | jq ".repoUrl" | tr -d '"')
  REPO_CATALOG=$(echo "$REPO_RUNTIME_CONFIG" | jq ".catalog" | tr -d '"')
  REPO_IDENTIFIER=$(echo "$REPO_RUNTIME_CONFIG" | jq ".identifier" | tr -d '"')
  REPO_STORAGE_PATH=$(echo "$REPO_RUNTIME_CONFIG" | jq ".repo.storagePath" | tr -d '"')

  # use identifier if set, otherwise extract repo name from url
  if [[ -n "$REPO_IDENTIFIER" ]] && [[ "$REPO_IDENTIFIER" != "null" ]]; then
    REPO_NAME="$REPO_IDENTIFIER"
  else
    REPO_NAME=$(basename "$REPO_URL" | sed 's/\.git$//')
  fi
  
  # storage path consists of catalog and identifier/name
  REPO_LOCAL_PATH="${REPO_STORAGE_PATH}/${REPO_CATALOG}/${REPO_NAME}"
  if [[ $DRY_RUN != "true" ]]; then
    mkdir -p "$(dirname "$REPO_LOCAL_PATH")"
  else
    op_prompt_debug "Creating directory '$REPO_LOCAL_PATH' (dry-run)"
  fi

  # print repo init message
  op_prompt_checkpoint "Process repo ${BOLD}${GREEN}${REPO_NAME}${NC}"
  op_prompt_info "Remote URL: ${BOLD}${REPO_URL}${NC}"
  op_prompt_info "Storage Path: ${BOLD}${REPO_LOCAL_PATH}${NC}"
  echo -e ""

  # assemble git command
  local CMD_GIT_CLONE_REPO="git clone $REPO_URL $REPO_LOCAL_PATH"
  local CMD_GIT_PULL="git -C $REPO_LOCAL_PATH pull"

  if [[ ! -d "$REPO_LOCAL_PATH" ]]; then
    # clone repo if directory not exist
    op_prompt_debug "Project repository not initialized, clone repo to target path"
    op_run_tracked_cmd "$CMD_GIT_CLONE_REPO"
  elif [[ -d $REPO_LOCAL_PATH/.git ]]; then
    # validate if local repo is already initalized if directory exist
    op_prompt_debug "Project repository is initialized, try update with git"
    op_run_tracked_cmd "$CMD_GIT_PULL"
  else
    op_prompt_debug "Project repository not initialized, try clone into the directory"
    op_run_tracked_cmd "$CMD_GIT_CLONE_REPO"
  fi

  # Check if mirror sync is disabled by execution mode
  if [[ "$SKIP_MIRROR_SYNC" == "true" ]]; then
    return 0
  fi
  
  # Check if mirror field exists and is not null
  MIRROR_EXISTS=$(echo "$REPO_RUNTIME_CONFIG" | jq 'has("mirror")')
  if [[ "$MIRROR_EXISTS" != "true" ]]; then
    op_prompt_info "No mirror configuration found, skipping mirror sync"
    return 0
  fi
  
  # Traverse sync mirror remote repo list
  MIRROR_LENGTH=$(echo "$REPO_RUNTIME_CONFIG" | jq '.mirror | length')
  # Check if mirror is null or empty
  if [[ "$MIRROR_LENGTH" == "null" ]] || [[ "$MIRROR_LENGTH" == "0" ]] || [[ -z "$MIRROR_LENGTH" ]]; then
    op_prompt_info "Mirror configuration is empty, skipping mirror sync"
    return 0
  fi
  
  local MIRROR_INDEX MIRROR_REMOTE_REPO_NAME MIRROR_REMOTE_REPO_URL MIRROR_FORCE_PUSH
  for ((MIRROR_INDEX = 0; MIRROR_INDEX < MIRROR_LENGTH; MIRROR_INDEX++)); do
    # mirror configuration
    MIRROR_REMOTE_REPO_NAME=$(echo "$REPO_RUNTIME_CONFIG" | jq ".mirror[$MIRROR_INDEX].name" | tr -d '"')
    MIRROR_REMOTE_REPO_URL=$(echo "$REPO_RUNTIME_CONFIG" | jq ".mirror[$MIRROR_INDEX].repoUrl" | tr -d '"')
    MIRROR_FORCE_PUSH=$(echo "$REPO_RUNTIME_CONFIG" | jq ".mirror[$MIRROR_INDEX].forcePush" | tr -d '"')
    if [[ -z $MIRROR_REMOTE_REPO_NAME ]] || [[ -z $MIRROR_REMOTE_REPO_URL ]]; then
      op_prompt_warn "Mirror repository configuration is not complete, abort this mirror"
      continue
    fi
    op_set_remote_repo "$REPO_LOCAL_PATH" "$MIRROR_REMOTE_REPO_NAME" "$MIRROR_REMOTE_REPO_URL"
    op_push_remote_repo "$REPO_NAME" "$REPO_LOCAL_PATH" "$MIRROR_REMOTE_REPO_NAME" "$MIRROR_FORCE_PUSH"
  done
}

# operation to setup remote repo if not set
op_set_remote_repo() {
  local REPO_LOCAL_PATH MIRROR_REMOTE_REPO_NAME MIRROR_REMOTE_REPO_URL
  REPO_LOCAL_PATH=${1}
  MIRROR_REMOTE_REPO_NAME=${2}
  MIRROR_REMOTE_REPO_URL=${3}

  # check if remote repo has been configured already
  if ! git -C "$REPO_LOCAL_PATH" remote | grep -q "^$MIRROR_REMOTE_REPO_NAME$"; then
    op_prompt_checkpoint "Setup remote repo ${BOLD}${GREEN}${MIRROR_REMOTE_REPO_NAME}${NC}"
    echo -e "${MIRROR_REMOTE_REPO_NAME}: ${BOLD}${MIRROR_REMOTE_REPO_URL}${NC}"
    local CMD_ADD_REMOTE_REPO="git -C $REPO_LOCAL_PATH remote add $MIRROR_REMOTE_REPO_NAME $MIRROR_REMOTE_REPO_URL"
    op_run_tracked_cmd "$CMD_ADD_REMOTE_REPO"
  else
    op_prompt_checkpoint "Remote repo ${BOLD}${BLUE}${MIRROR_REMOTE_REPO_NAME}${NC} already setup"
    echo -e "${MIRROR_REMOTE_REPO_NAME}: ${BOLD}${MIRROR_REMOTE_REPO_URL}${NC}"
  fi
}

# push to remote repo
op_push_remote_repo() {
  local REPO_NAME REPO_LOCAL_PATH MIRROR_REMOTE_REPO_NAME REPO_BRANCH_NAME MIRROR_FORCE_PUSH
  REPO_NAME="${1}"
  REPO_LOCAL_PATH="${2}"
  MIRROR_REMOTE_REPO_NAME="${3}"
  MIRROR_FORCE_PUSH="${4}"
  REPO_BRANCH_NAME=$(git -C "$REPO_LOCAL_PATH" rev-parse --abbrev-ref HEAD)

  # print repo sync message
  op_prompt_checkpoint "Sync repo ${BOLD}${GREEN}${REPO_NAME}${NC} to remote repo ${BOLD}${BLUE}${MIRROR_REMOTE_REPO_NAME}${NC}"
  # echo -e "Project path: ${BOLD}${REPO_LOCAL_PATH}${NC}"
  echo -e "Tracking branch: ${BLUE}${REPO_BRANCH_NAME}${NC}"

  # assemble git command
  local CMD_GIT_RESET_HEADER="git -C $REPO_LOCAL_PATH reset --hard origin/$REPO_BRANCH_NAME"
  local CMD_GIT_PUSH_TO_MIRROR="git -C $REPO_LOCAL_PATH push $MIRROR_REMOTE_REPO_NAME"
  local CMD_GIT_FORCE_PUSH_TO_MIRROR="git -C $REPO_LOCAL_PATH push $MIRROR_REMOTE_REPO_NAME --force"

  # run command
  op_run_tracked_cmd "$CMD_GIT_RESET_HEADER"
  if [[ "$MIRROR_FORCE_PUSH" == "true" ]]; then
    op_prompt_warn "Force push enabled for remote ${MIRROR_REMOTE_REPO_NAME}"
    op_run_tracked_cmd "$CMD_GIT_FORCE_PUSH_TO_MIRROR"
  else
    op_run_tracked_cmd "$CMD_GIT_PUSH_TO_MIRROR"
  fi
}

# load repo config, inherit from global config and overwrite the custom repo config
op_load_repo_config() {
  local REPO_CONFIG_CONTENT="${1}"
  echo "$REPO_CONFIG_CONTENT" >"${TEMP_PATH}/repo.temp.json"
  # deep copy and overwrite (currently the most clear way to implement)
  REPO_RUNTIME_CONFIG=$(jq -s '.[0] * .[1]' "${TEMP_PATH}/global.temp.json" "${TEMP_PATH}/repo.temp.json")
  echo "$REPO_RUNTIME_CONFIG"
}

# load an access token from a file into a named variable
# Parameters:
#   $1 - token file path   (e.g. "$DATA_PATH/github/github-access-token")
#   $2 - variable name     (e.g. GITHUB_ACCESS_TOKEN)
#   $3 - platform label    (e.g. "GitHub")
op_load_access_token() {
  local TOKEN_FILE="${1}"
  local VAR_NAME="${2}"
  local PLATFORM="${3}"

  if [[ -f "$TOKEN_FILE" ]]; then
    eval "${VAR_NAME}=\"$(cat "$TOKEN_FILE")\""
  fi

  if [[ -z "$(eval echo "\$$VAR_NAME")" ]]; then
    op_prompt_warn "${PLATFORM} access token file not found or empty. You may encounter rate limit issues."
    sleep 2
  fi
}

# common handler for all platform repo operations (sync, release downloads, tag downloads)
# Parameters:
#   $1 - REPO_RUNTIME_CONFIG (JSON string)
#   $2 - download_release function name  (e.g. op_github_download_release)
#   $3 - download_tag function name      (e.g. op_github_download_tag)
op_handle_repo() {
  local REPO_RUNTIME_CONFIG FN_DOWNLOAD_RELEASE FN_DOWNLOAD_TAG
  REPO_RUNTIME_CONFIG="${1}"
  FN_DOWNLOAD_RELEASE="${2}"
  FN_DOWNLOAD_TAG="${3}"

  local REPO_URL REPO_SYNC REPO_RELEASE_DOWNLOAD REPO_TAG_DOWNLOAD
  REPO_URL=$(echo "$REPO_RUNTIME_CONFIG" | jq ".repoUrl" | tr -d '"')
  REPO_SYNC=$(echo "$REPO_RUNTIME_CONFIG" | jq ".repo.sync" | tr -d '"')
  REPO_RELEASE_DOWNLOAD=$(echo "$REPO_RUNTIME_CONFIG" | jq ".release.download" | tr -d '"')
  REPO_TAG_DOWNLOAD=$(echo "$REPO_RUNTIME_CONFIG" | jq ".tag.download" | tr -d '"')

  if [[ "$REPO_SYNC" == "true" ]]; then
    op_sync_repo "$REPO_RUNTIME_CONFIG"
  fi

  if [[ "$REPO_RELEASE_DOWNLOAD" == "true" ]]; then
    local RELEASE_STORAGE_PATH RELEASE_EXCLUDE_KEYWORDS RELEASE_KEPT_VERSION_NUM RELEASE_KEPT_VERSIONS
    RELEASE_STORAGE_PATH=$(echo "$REPO_RUNTIME_CONFIG" | jq ".release.storagePath" | tr -d '"')
    RELEASE_EXCLUDE_KEYWORDS=$(echo "$REPO_RUNTIME_CONFIG" | jq -r '.release.excludeKeywords // [] | join(",")')
    RELEASE_KEPT_VERSION_NUM=$(echo "$REPO_RUNTIME_CONFIG" | jq ".release.keptVersionNum" | tr -d '"')
    RELEASE_KEPT_VERSIONS=$(echo "$REPO_RUNTIME_CONFIG" | jq -r '.release.keptVersionKeywords // [] | join(",")')
    "$FN_DOWNLOAD_RELEASE" "$REPO_URL" "$RELEASE_STORAGE_PATH" "$RELEASE_EXCLUDE_KEYWORDS" "$REPO_IDENTIFIER" "$RELEASE_KEPT_VERSION_NUM" "$REPO_CATALOG" "$RELEASE_KEPT_VERSIONS"
  fi

  if [[ "$REPO_TAG_DOWNLOAD" == "true" ]]; then
    local TAG_STORAGE_PATH TAG_KEPT_VERSION_NUM TAG_KEPT_VERSIONS
    TAG_STORAGE_PATH=$(echo "$REPO_RUNTIME_CONFIG" | jq ".tag.storagePath" | tr -d '"')
    TAG_KEPT_VERSION_NUM=$(echo "$REPO_RUNTIME_CONFIG" | jq ".tag.keptVersionNum" | tr -d '"')
    TAG_KEPT_VERSIONS=$(echo "$REPO_RUNTIME_CONFIG" | jq -r '.tag.keptVersionKeywords // [] | join(",")')
    "$FN_DOWNLOAD_TAG" "$REPO_URL" "$TAG_STORAGE_PATH" "$REPO_IDENTIFIER" "$TAG_KEPT_VERSION_NUM" "$REPO_CATALOG" "$TAG_KEPT_VERSIONS"
  fi
}

# handle config data for a single repo
op_dispatch_repo() {
  local REPO_DATA REPO_RUNTIME_CONFIG REPO_URL
  REPO_DATA="$*"
  REPO_RUNTIME_CONFIG=$(op_load_repo_config "$REPO_DATA")
  REPO_URL=$(echo "$REPO_DATA" | jq ".repoUrl" | tr -d '"')

  # reset per-repo status before processing
  REPO_PROCESS_STATUS="success"

  if [[ "$REPO_URL" == *"github.com"* ]]; then
    op_handle_github_repo "$REPO_RUNTIME_CONFIG"
  elif [[ "$REPO_URL" == *"gitlab.com"* ]] || [[ "$REPO_URL" == *"gitlab."* ]]; then
    op_handle_gitlab_repo "$REPO_RUNTIME_CONFIG"
  else
    op_handle_general_repo "$REPO_RUNTIME_CONFIG"
  fi
}

# cleanup old versions, keep only the newest N versions and specific pinned versions
op_cleanup_old_versions() {

  local STORAGE_PATH REPO_IDENTIFIER KEPT_VERSION_NUM TYPE KEPT_VERSIONS
  STORAGE_PATH="${1}"
  REPO_IDENTIFIER="${2}"
  KEPT_VERSION_NUM="${3}"
  TYPE="${4:-version}"
  KEPT_VERSIONS="${5}"

  # default to 5 if not set or invalid
  if [[ -z "$KEPT_VERSION_NUM" || "$KEPT_VERSION_NUM" == "null" ]]; then
    KEPT_VERSION_NUM=5
  fi
  
  op_prompt_checkpoint -n "Cleanup old ${TYPE}, keep only the newest ${BOLD}${GREEN}${KEPT_VERSION_NUM}${NC} ${TYPE}"

  if [[ -d "$STORAGE_PATH/$REPO_IDENTIFIER" ]]; then
    local VERSION_DIRS
    VERSION_DIRS=($(ls -1dt "$STORAGE_PATH/$REPO_IDENTIFIER"/*/ 2>/dev/null))

    # build list of pinned version names that must not be deleted
    local PINNED_VERSIONS=()
    if [[ -n "$KEPT_VERSIONS" && "$KEPT_VERSIONS" != "null" ]]; then
      IFS=',' read -A PINNED_VERSIONS <<<"$KEPT_VERSIONS"
    fi

    # separate dirs into eligible-for-cleanup and pinned
    local ELIGIBLE_DIRS=()
    for DIR in "${VERSION_DIRS[@]}"; do
      local DIR_NAME IS_PINNED
      DIR_NAME=$(basename "$DIR")
      IS_PINNED=false
      for PINNED_VER in "${PINNED_VERSIONS[@]}"; do
        if [[ "$DIR_NAME" == "$PINNED_VER" ]]; then
          IS_PINNED=true
          break
        fi
      done
      if [[ "$IS_PINNED" == "false" ]]; then
        ELIGIBLE_DIRS+=("$DIR")
      fi
    done

    # report pinned versions
    for PINNED_VER in "${PINNED_VERSIONS[@]}"; do
      if [[ -d "$STORAGE_PATH/$REPO_IDENTIFIER/$PINNED_VER" ]]; then
        op_prompt_info "Keeping pinned ${TYPE}: ${BOLD}${GREEN}${PINNED_VER}${NC}"
      fi
    done

    REMOVE_COUNT=0

    if (( ${#ELIGIBLE_DIRS[@]} > KEPT_VERSION_NUM )); then
      op_prompt_info "Keeping ${KEPT_VERSION_NUM} newest ${TYPE}(s), removing $((${#ELIGIBLE_DIRS[@]} - KEPT_VERSION_NUM)) old ${TYPE}(s)"
      for DIR in "${ELIGIBLE_DIRS[@]:KEPT_VERSION_NUM}"; do
        op_prompt_info "Removing old ${TYPE}: $(basename "$DIR")"
        rm -rf "$DIR"
        REMOVE_COUNT+=1
      done
    fi

    if [[ "$REMOVE_COUNT" -eq 0 ]]; then
      op_prompt_info "No old ${TYPE} to remove, all eligible ${TYPE} are within the kept version number limit"
    fi
  fi
}
