#!/usr/bin/env zsh

op_prompt_checkpoint() {
  echo -e "${BLUE}==>${NC} ${BOLD}${WHITE}${1}${NC}"
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
  # print command on console
  echo -e "\n${GREY}${CMD_STR}${NC}\n"

  if [[ "$DRY_RUN" != true ]]; then
    if ! zsh -c "$CMD_STR"; then
      op_prompt_error "Error: command execute failure"
      return 1
    fi
  fi
}

op_run_cmd_with_result() {
  local CMD_STR=${*}
  # print command on console
  echo -e "\n${GREY}${CMD_STR}${NC}\n"

  if [[ "$DRY_RUN" != true ]]; then
    SYNC_EXEC_STDOUT=$(zsh -c "$CMD_STR")
    export SYNC_EXEC_STDOUT
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
  echo -e "\n--------------- $EXECUTE_TIME ---------------\n"
  LOG_FILE="$LOG_PATH/sync.log"
  mkdir -p "$LOG_PATH"
  if [[ ! -f $LOG_FILE ]]; then
    touch "$LOG_FILE"
  fi
}

# load setting from global config file and in-line parameter
op_load_runtime_config() {
  local RUNTIME_CONFIG_FILE GLOBAL_RUNTIME_CONFIG
  RUNTIME_CONFIG_FILE="${1}"
  GLOBAL_RUNTIME_CONFIG=$(jq -s '.[0] * .[1]' "$GLOBAL_CONFIG_FILE" "$RUNTIME_CONFIG_FILE")
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

  # TODO parse and start automation
  if [[ "$REPO_URL" == *"github.com"* ]]; then
    op_handle_github_repo "$REPO_RUNTIME_CONFIG"
  elif [[ "$REPO_URL" == *"gitlab.com"* ]]; then
    echo "wip"
  elif [[ "$REPO_URL" == *"gitee.com"* ]]; then
    echo "wip"
  fi
}

op_handle_github_repo() {
  local REPO_RUNTIME_CONFIG REPO_SYNC REPO_RELEASE_DOWNLOAD REPO_TAG_DOWNLOAD
  REPO_RUNTIME_CONFIG="$*"
  REPO_SYNC=$(echo "$REPO_RUNTIME_CONFIG" | jq ".repo.sync" | tr -d '"')
  REPO_RELEASE_DOWNLOAD=$(echo "$REPO_RUNTIME_CONFIG" | jq ".release.download" | tr -d '"')
  REPO_TAG_DOWNLOAD=$(echo "$REPO_RUNTIME_CONFIG" | jq ".tag.download" | tr -d '"')

  if [[ "$REPO_SYNC" == "true" ]]; then
    op_process_git_repo "$REPO_RUNTIME_CONFIG"
  fi

  if [[ "$REPO_RELEASE_DOWNLOAD" == "true" ]]; then
    echo "wip"
  fi

  if [[ "$REPO_TAG_DOWNLOAD" == "true" ]]; then
    echo "wip"
  fi

  # TODO add mirror handle

}

# initialize local repo
op_process_git_repo() {
  local REPO_RUNTIME_CONFIG REPO_IDENTIFIER REPO_CATALOG REPO_STORAGE_PATH REPO_LOCAL_PATH
  REPO_RUNTIME_CONFIG="$*"
  REPO_URL=$(echo "$REPO_RUNTIME_CONFIG" | jq ".repoUrl" | tr -d '"')
  REPO_CATALOG=$(echo "$REPO_RUNTIME_CONFIG" | jq ".catalog" | tr -d '"')
  REPO_IDENTIFIER=$(echo "$REPO_RUNTIME_CONFIG" | jq ".identifier" | tr -d '"')
  REPO_STORAGE_PATH=$(echo "$REPO_RUNTIME_CONFIG" | jq ".repo.storagePath" | tr -d '"')

  # extract repo identifier from url if not set
  if [[ -z "$REPO_IDENTIFIER" ]]; then
    REPO_IDENTIFIER=$(op_github_extract_repo_identifier "$REPO_URL")
  fi
  # storage path will consists of catalog and marked by identifier
  REPO_LOCAL_PATH="${REPO_STORAGE_PATH}/${REPO_CATALOG}/${REPO_IDENTIFIER}"
  if [[ $DRY_RUN != "true" ]]; then
    mkdir -p "$(dirname "$REPO_LOCAL_PATH")"
  else
    op_prompt_debug "Creating directory '$REPO_LOCAL_PATH' (dry-run)"
  fi

  # print repo init message
  op_prompt_checkpoint "Initialize project ${BOLD}${GREEN}${REPO_IDENTIFIER}${NC} to local path ${BOLD}${BLUE}${REPO_LOCAL_PATH}${NC}"

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
  MIRROR_LENGTH=$(echo "$REPO_DATA" | jq '.mirror | length')
  local MIRROR_INDEX MIRROR_REMOTE_REPO_NAME MIRROR_REMOTE_REPO_URL
  for ((MIRROR_INDEX = 0; MIRROR_INDEX < MIRROR_LENGTH; MIRROR_INDEX++)); do
    # mirror configuration
    MIRROR_REMOTE_REPO_NAME=$(echo "$REPO_DATA" | jq ".mirror[$MIRROR_INDEX].repoName" | tr -d '"')
    MIRROR_REMOTE_REPO_URL=$(echo "$REPO_DATA" | jq ".mirror[$MIRROR_INDEX].repoUrl" | tr -d '"')
    if [[ -z $MIRROR_REMOTE_REPO_NAME ]] || [[ -z $MIRROR_REMOTE_REPO_URL ]]; then
      op_prompt_warn "Mirror repository configuration is not complete, abort this mirror"
      return 0
    fi
    op_set_remote_repo "$REPO_LOCAL_PATH" "$MIRROR_REMOTE_REPO_NAME" "$MIRROR_REMOTE_REPO_URL"
    op_push_remote_repo "$REPO_IDENTIFIER" "$REPO_LOCAL_PATH" "$MIRROR_REMOTE_REPO_NAME"
  done
}

# operation to setup remote repo
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
    op_run_cmd "$CMD_ADD_REMOTE_REPO"
  else
    op_prompt_checkpoint "Remote repo already setup ${BOLD}${GREEN}${MIRROR_REMOTE_REPO_NAME}${NC}"
    echo -e "${MIRROR_REMOTE_REPO_NAME}: ${BOLD}${MIRROR_REMOTE_REPO_URL}${NC}"
  fi
}

# push to remote repo
op_push_remote_repo() {
  local REPO_IDENTIFIER REPO_LOCAL_PATH  MIRROR_REMOTE_REPO_NAME REPO_BRANCH_NAME
  REPO_IDENTIFIER="${1}"
  REPO_LOCAL_PATH="${2}"
  MIRROR_REMOTE_REPO_NAME="${3}"
  REPO_BRANCH_NAME=$(git -C "$REPO_LOCAL_PATH" rev-parse --abbrev-ref HEAD)

  # print repo sync message
  op_prompt_checkpoint "Sync project ${BOLD}${GREEN}${REPO_IDENTIFIER}${NC} to remote repo ${BOLD}${BLUE}${MIRROR_REMOTE_REPO_NAME}${NC}"
  echo -e "Project path: ${BOLD}${REPO_LOCAL_PATH}${NC}"
  echo -e "Tracking branch: ${BLUE}${REPO_BRANCH_NAME}${NC}"

  # assemble git command
  local CMD_GIT_RESET_HEADER="git -C $REPO_LOCAL_PATH reset --hard origin/$REPO_BRANCH_NAME"
  local CMD_GIT_PUSH_TO_MIRROR="git -C $REPO_LOCAL_PATH push $MIRROR_REMOTE_REPO_NAME"

  # run command
  op_run_cmd "$CMD_GIT_RESET_HEADER"
  if [[ $SYNC_MIRROR == true ]]; then
    op_run_cmd "$CMD_GIT_PUSH_TO_MIRROR"
  fi
}

# operation to extract release storage path config from repo
op_extract_release_storage_path() {
  local REPO_DATA REPO_RELEASE_STORAGE
  REPO_DATA="${1}"

  REPO_RELEASE_STORAGE=$(echo "$REPO_DATA" | jq ".releaseStoragePath" | tr -d '"')

  # apply default release storage path if not configured
  if [[ -z "$REPO_RELEASE_STORAGE" ]] || [[ "$REPO_RELEASE_STORAGE" == "null" ]]; then
    REPO_RELEASE_STORAGE="$DEFAULT_RELEASE_STORAGE"
  fi
  echo "$REPO_RELEASE_STORAGE"
}
