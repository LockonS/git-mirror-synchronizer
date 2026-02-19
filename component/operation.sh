#!/usr/bin/env zsh

op_prompt_checkpoint() {
  echo -e "${BLUE}==>${NC} ${WHITE}${1}${NC}"
}

op_prompt_debug() {
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
  local CMD_STR=${*}

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

op_run_cmd_with_result() {
  local CMD_STR=${*}

  if [[ "$DRY_RUN" != true ]]; then
    SYNC_EXEC_STDOUT=$(zsh -c "$CMD_STR")
    export SYNC_EXEC_STDOUT
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
  fi
}

op_runtime_prepare() {
  echo -e "\n--------------------- $OPERATION_TIME ---------------------\n"
  mkdir -p "$TEMP_PATH"
  mkdir -p "$LOG_PATH"

  LOG_FILE="$LOG_PATH/sync.log"
  if [[ ! -f $LOG_FILE ]]; then
    touch "$LOG_FILE"
  fi

  if [[ ! -f "$DEFAULT_CONFIG_FILE" ]]; then
    op_prompt_checkpoint "Default config file not found, creating from global config template" 
    op_prompt_debug "Global config file: ${GREEN}${GLOBAL_CONFIG_FILE}${NC}"
    cp "$GLOBAL_CONFIG_FILE" "$DEFAULT_CONFIG_FILE"
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

# load repo config, inherit from global config and overwrite the custom repo config
op_load_repo_config() {
  local REPO_CONFIG_CONTENT="${1}"
  echo "$REPO_CONFIG_CONTENT" >"${TEMP_PATH}/repo.temp.json"
  # deep copy and overwrite (currently the most clear way to implement)
  REPO_RUNTIME_CONFIG=$(jq -s '.[0] * .[1]' "${TEMP_PATH}/global.temp.json" "${TEMP_PATH}/repo.temp.json")
  echo "$REPO_RUNTIME_CONFIG"
}

# handle config data for a single repo
op_handle_repo_data() {
  local REPO_DATA REPO_RUNTIME_CONFIG REPO_URL
  REPO_DATA="$*"
  REPO_RUNTIME_CONFIG=$(op_load_repo_config "$REPO_DATA")
  REPO_URL=$(echo "$REPO_DATA" | jq ".repoUrl" | tr -d '"')

  if [[ "$REPO_URL" == *"github.com"* ]]; then
    op_handle_github_repo "$REPO_RUNTIME_CONFIG"
  elif [[ "$REPO_URL" == *"gitlab.com"* ]]; then
    echo "gitlab module not supported yet"
  elif [[ "$REPO_URL" == *"gitee.com"* ]]; then
    echo "gitee module not supported yet"
  fi
}

op_handle_github_repo() {
  local REPO_RUNTIME_CONFIG REPO_SYNC REPO_RELEASE_DOWNLOAD REPO_TAG_DOWNLOAD REPO_IDENTIFIER REPO_CATALOG
  REPO_RUNTIME_CONFIG="$*"
  REPO_URL=$(echo "$REPO_RUNTIME_CONFIG" | jq ".repoUrl" | tr -d '"')
  REPO_SYNC=$(echo "$REPO_RUNTIME_CONFIG" | jq ".repo.sync" | tr -d '"')
  REPO_RELEASE_DOWNLOAD=$(echo "$REPO_RUNTIME_CONFIG" | jq ".release.download" | tr -d '"')
  REPO_TAG_DOWNLOAD=$(echo "$REPO_RUNTIME_CONFIG" | jq ".tag.download" | tr -d '"')
  REPO_IDENTIFIER=$(echo "$REPO_RUNTIME_CONFIG" | jq ".identifier" | tr -d '"')
  REPO_CATALOG=$(echo "$REPO_RUNTIME_CONFIG" | jq ".catalog" | tr -d '"')

  if [[ "$REPO_SYNC" == "true" ]]; then
    op_process_git_repo "$REPO_RUNTIME_CONFIG"
  fi

  if [[ "$REPO_RELEASE_DOWNLOAD" == "true" ]]; then
    RELEASE_STORAGE_PATH=$(echo "$REPO_RUNTIME_CONFIG" | jq ".release.storagePath" | tr -d '"')
    RELEASE_EXCLUDE_KEYWORDS=$(echo "$REPO_RUNTIME_CONFIG" | jq ".release.excludeKeywords" | tr -d '"')
    RELEASE_KEPT_VERSION_NUM=$(echo "$REPO_RUNTIME_CONFIG" | jq ".release.keptVersionNum" | tr -d '"')
    op_github_download_release "$REPO_URL" "$RELEASE_STORAGE_PATH" "$RELEASE_EXCLUDE_KEYWORDS" "$REPO_IDENTIFIER" "$RELEASE_KEPT_VERSION_NUM" "$REPO_CATALOG"
  fi

  if [[ "$REPO_TAG_DOWNLOAD" == "true" ]]; then
    TAG_STORAGE_PATH=$(echo "$REPO_RUNTIME_CONFIG" | jq ".tag.storagePath" | tr -d '"')
    TAG_KEPT_VERSION_NUM=$(echo "$REPO_RUNTIME_CONFIG" | jq ".tag.keptVersionNum" | tr -d '"')
    op_github_download_tag "$REPO_URL" "$TAG_STORAGE_PATH" "$REPO_IDENTIFIER" "$TAG_KEPT_VERSION_NUM" "$REPO_CATALOG"
  fi
}

# initialize local repo
op_process_git_repo() {
  local REPO_RUNTIME_CONFIG REPO_NAME REPO_IDENTIFIER REPO_CATALOG REPO_STORAGE_PATH REPO_LOCAL_PATH
  REPO_RUNTIME_CONFIG="$*"
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
  op_prompt_info "Local path: ${BOLD}${REPO_LOCAL_PATH}${NC}"

  # assemble git command
  local CMD_GIT_CLONE_REPO="git clone $REPO_URL $REPO_LOCAL_PATH"
  local CMD_GIT_PULL="git -C $REPO_LOCAL_PATH pull"

  if [[ ! -d "$REPO_LOCAL_PATH" ]]; then
    # clone repo if directory not exist
    op_prompt_debug "Project repository not initialized, clone repo to target path"
    op_run_cmd "$CMD_GIT_CLONE_REPO"
  elif [[ -d $REPO_LOCAL_PATH/.git ]]; then
    # validate if local repo is already initalized if directory exist
    op_prompt_debug "Project repository is initialized, try update with git"
    op_run_cmd "$CMD_GIT_PULL"
  else
    op_prompt_debug "Project repository not initialized, try clone into the directory"
    op_run_cmd "$CMD_GIT_CLONE_REPO"
  fi

  # traverse sync mirror remote repo list
  # Check if mirror field exists and is not null
  MIRROR_EXISTS=$(echo "$REPO_DATA" | jq 'has("mirror")')
  if [[ "$MIRROR_EXISTS" != "true" ]]; then
    op_prompt_debug "No mirror configuration found, skipping mirror sync"
    return 0
  fi
  
  MIRROR_LENGTH=$(echo "$REPO_DATA" | jq '.mirror | length')
  # Check if mirror is null or empty
  if [[ "$MIRROR_LENGTH" == "null" ]] || [[ "$MIRROR_LENGTH" == "0" ]] || [[ -z "$MIRROR_LENGTH" ]]; then
    op_prompt_debug "Mirror configuration is empty, skipping mirror sync"
    return 0
  fi
  
  local MIRROR_INDEX MIRROR_REMOTE_REPO_NAME MIRROR_REMOTE_REPO_URL MIRROR_FORCE_PUSH
  for ((MIRROR_INDEX = 0; MIRROR_INDEX < MIRROR_LENGTH; MIRROR_INDEX++)); do
    # mirror configuration
    MIRROR_REMOTE_REPO_NAME=$(echo "$REPO_DATA" | jq ".mirror[$MIRROR_INDEX].name" | tr -d '"')
    MIRROR_REMOTE_REPO_URL=$(echo "$REPO_DATA" | jq ".mirror[$MIRROR_INDEX].repoUrl" | tr -d '"')
    MIRROR_FORCE_PUSH=$(echo "$REPO_DATA" | jq ".mirror[$MIRROR_INDEX].forcePush" | tr -d '"')
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

  echo -e ""
  # check if remote repo has been configured already
  if ! git -C "$REPO_LOCAL_PATH" remote | grep -q "^$MIRROR_REMOTE_REPO_NAME$"; then
    op_prompt_checkpoint "Setup remote repo ${BOLD}${GREEN}${MIRROR_REMOTE_REPO_NAME}${NC}"
    echo -e "${MIRROR_REMOTE_REPO_NAME}: ${BOLD}${MIRROR_REMOTE_REPO_URL}${NC}"
    local CMD_ADD_REMOTE_REPO="git -C $REPO_LOCAL_PATH remote add $MIRROR_REMOTE_REPO_NAME $MIRROR_REMOTE_REPO_URL"
    op_run_cmd "$CMD_ADD_REMOTE_REPO"
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
  echo -e ""
  op_prompt_checkpoint "Sync repo ${BOLD}${GREEN}${REPO_NAME}${NC} to remote repo ${BOLD}${BLUE}${MIRROR_REMOTE_REPO_NAME}${NC}"
  # echo -e "Project path: ${BOLD}${REPO_LOCAL_PATH}${NC}"
  echo -e "Tracking branch: ${BLUE}${REPO_BRANCH_NAME}${NC}"

  # assemble git command
  local CMD_GIT_RESET_HEADER="git -C $REPO_LOCAL_PATH reset --hard origin/$REPO_BRANCH_NAME"
  local CMD_GIT_PUSH_TO_MIRROR="git -C $REPO_LOCAL_PATH push $MIRROR_REMOTE_REPO_NAME"
  local CMD_GIT_FORCE_PUSH_TO_MIRROR="git -C $REPO_LOCAL_PATH push $MIRROR_REMOTE_REPO_NAME --force"

  # run command
  op_run_cmd "$CMD_GIT_RESET_HEADER"
  if [[ $SYNC_MIRROR == "true" ]]; then
    if [[ "$MIRROR_FORCE_PUSH" == "true" ]]; then
      op_run_cmd "$CMD_GIT_FORCE_PUSH_TO_MIRROR"
    else
      op_run_cmd "$CMD_GIT_PUSH_TO_MIRROR"
    fi
  fi
}


# cleanup old versions, keep only the newest N versions
op_cleanup_old_versions() {
  local STORAGE_PATH REPO_IDENTIFIER KEPT_VERSION_NUM TYPE
  STORAGE_PATH="${1}"
  REPO_IDENTIFIER="${2}"
  KEPT_VERSION_NUM="${3}"
  TYPE="${4:-version}"

  # default to 3 if not set or invalid
  if [[ -z "$KEPT_VERSION_NUM" || "$KEPT_VERSION_NUM" == "null" ]]; then
    KEPT_VERSION_NUM=3
  fi

  if [[ -d "$STORAGE_PATH/$REPO_IDENTIFIER" ]]; then
    local VERSION_DIRS
    VERSION_DIRS=($(ls -1dt "$STORAGE_PATH/$REPO_IDENTIFIER"/*/ 2>/dev/null))
    if (( ${#VERSION_DIRS[@]} > KEPT_VERSION_NUM )); then
      op_prompt_info "Keeping ${KEPT_VERSION_NUM} newest ${TYPE}(s), removing $((${#VERSION_DIRS[@]} - KEPT_VERSION_NUM)) old ${TYPE}(s)"
      for DIR in "${VERSION_DIRS[@]:KEPT_VERSION_NUM}"; do
        op_prompt_info "Removing old ${TYPE}: $(basename "$DIR")"
        rm -rf "$DIR"
      done
    fi
  fi
}