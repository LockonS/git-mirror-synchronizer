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

# load setting from config file and in-line parameter
op_load_runtime_setting() {
  local CONFIG_FILE
  CONFIG_FILE="${1}"
}

# initialize local repo
op_init_local_repo() {
  local REPO_NAME REPO_LOCAL_PATH TRACK_REMOTE_REPO_NAME TRACK_REMOTE_REPO_URL
  REPO_NAME="${1}"
  REPO_LOCAL_PATH="${2}"
  TRACK_REMOTE_REPO_NAME="${3}"
  TRACK_REMOTE_REPO_URL="${4}"

  # print repo init message
  op_prompt_checkpoint "Initialize project ${BOLD}${GREEN}${REPO_NAME}${NC} to local path ${BOLD}${BLUE}${REPO_LOCAL_PATH}${NC}"
  mkdir -p "$(dirname "$REPO_LOCAL_PATH")"

  # validate if local repo is properly initalized
  if [[ -d $REPO_LOCAL_PATH/.git ]]; then
    op_prompt_debug "Project repository is initialized, abort clone process"
    return 0
  fi

  # assemble git command
  local CMD_GIT_CLONE_REPO="git clone $TRACK_REMOTE_REPO_URL $REPO_LOCAL_PATH"
  op_run_cmd "$CMD_GIT_CLONE_REPO"
}

# push to remote repo
op_push_remote_repo() {
  local REPO_NAME REPO_LOCAL_PATH TRACK_REMOTE_REPO_NAME MIRROR_REMOTE_REPO_NAME REPO_BRANCH_NAME
  REPO_NAME="${1}"
  REPO_LOCAL_PATH="${2}"
  TRACK_REMOTE_REPO_NAME="${3}"
  MIRROR_REMOTE_REPO_NAME="${4}"
  REPO_BRANCH_NAME=$(git -C "$REPO_LOCAL_PATH" rev-parse --abbrev-ref HEAD)

  # print repo sync message
  op_prompt_checkpoint "Sync project ${BOLD}${GREEN}${REPO_NAME}${NC} to remote repo ${BOLD}${BLUE}${MIRROR_REMOTE_REPO_NAME}${NC}"
  echo -e "Project path: ${BOLD}${REPO_LOCAL_PATH}${NC}"
  echo -e "Tracking branch: ${BLUE}${REPO_BRANCH_NAME}${NC}"

  # assemble git command
  local CMD_GIT_FETCH_UPDTE="git -C $REPO_LOCAL_PATH fetch $TRACK_REMOTE_REPO_NAME"
  local CMD_GIT_RESET_HEADER="git -C $REPO_LOCAL_PATH reset --hard $TRACK_REMOTE_REPO_NAME/$REPO_BRANCH_NAME"
  local CMD_GIT_PUSH_TO_MIRROR="git -C $REPO_LOCAL_PATH push $MIRROR_REMOTE_REPO_NAME"

  # run command
  op_run_cmd "$CMD_GIT_FETCH_UPDTE"
  op_run_cmd "$CMD_GIT_RESET_HEADER"
  if [[ $SYNC_MIRROR == true ]]; then
    op_run_cmd "$CMD_GIT_PUSH_TO_MIRROR"
  fi
}

# operation to setup remote repo
op_set_remote_repo() {
  local REPO_NAME MIRROR_REMOTE_REPO_NAME MIRROR_REMOTE_REPO_URL
  REPO_NAME=${1}
  REPO_LOCAL_PATH=${2}
  MIRROR_REMOTE_REPO_NAME=${3}
  MIRROR_REMOTE_REPO_URL=${4}

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

# operation to process a single git repo
op_process_git_repo() {
  local REPO_DATA EXECUTE_MODE SINGLE_PROJECT
  REPO_DATA="${1}"
  EXECUTE_MODE="${2}"
  SINGLE_PROJECT="${3}"

  # configuration variables
  local REPO_NAME REPO_LOCAL_PATH TRACK_REMOTE_REPO_NAME TRACK_REMOTE_REPO_URL MIRROR_LENGTH
  REPO_LOCAL_PATH=$(echo "$REPO_DATA" | jq '.repoLocalPath' | tr -d '"')
  TRACK_REMOTE_REPO_NAME=$(echo "$REPO_DATA" | jq '.trackRemoteRepoName' | tr -d '"')
  TRACK_REMOTE_REPO_URL=$(echo "$REPO_DATA" | jq '.trackRemoteRepoUrl' | tr -d '"')

  # validate configuration of tracking remote repo
  if [[ -z $REPO_LOCAL_PATH ]] || [[ -z $TRACK_REMOTE_REPO_NAME ]] || [[ -z $TRACK_REMOTE_REPO_URL ]]; then
    op_prompt_warn "Tracking repository configuration is not complete, abort task"
    return 0
  fi

  # read repo name from url
  REPO_NAME=$(basename "$TRACK_REMOTE_REPO_URL" | sed 's/\.git$//')
  if [[ -n "$SINGLE_PROJECT" ]]; then
    if [[ "$REPO_NAME" != "$SINGLE_PROJECT" ]]; then
      return 0
    fi
  fi

  MIRROR_LENGTH=$(echo "$REPO_DATA" | jq '.mirror | length')

  # download release artifacts
  local REPO_URL_MARKER REPO_RELEASE_STORAGE EXCLUDE_KEYWORDS
  if [[ $EXECUTE_MODE == "download" ]]; then
    local REPO_RELEASE_DOWNLOAD REPO_TAG_DOWNLOAD
    # release and tag asset download is disabled by default
    REPO_RELEASE_DOWNLOAD=$(echo "$REPO_DATA" | jq ".downloadRelease // \"false\"" | tr -d '"')
    REPO_TAG_DOWNLOAD=$(echo "$REPO_DATA" | jq ".downloadTag // \"false\"" | tr -d '"')

    if [[ "$TRACK_REMOTE_REPO_URL" != *github.com* ]]; then
      op_prompt_warn "Release download feature not supported for $TRACK_REMOTE_REPO_URL"
      return 0
    fi

    REPO_URL_MARKER=$(op_extract_repo_url_marker "$REPO_DATA")
    REPO_RELEASE_STORAGE=$(op_extract_release_storage_path "$REPO_DATA")
    EXCLUDE_KEYWORDS=$(echo "$REPO_DATA" | jq ".excludeKeywords" | tr -d '"')

    # judge if release download is enabled
    if [[ "$REPO_RELEASE_DOWNLOAD" == "true" ]]; then
      op_download_github_release "$REPO_URL_MARKER" "$REPO_RELEASE_STORAGE" "$EXCLUDE_KEYWORDS"
    else
      op_prompt_debug "This repo is configurated not to download the release artifacts"
    fi

    # judge if tag download is enabled
    if [[ "$REPO_TAG_DOWNLOAD" == "true" ]]; then
      op_download_github_tag "$REPO_URL_MARKER" "$REPO_RELEASE_STORAGE"
    else
      op_prompt_debug "This repo is configurated not to download the tag artifacts"
    fi

    return 0
  fi

  # initialize local repo
  if [[ $EXECUTE_MODE == "init" ]]; then
    op_init_local_repo "$REPO_NAME" "$REPO_LOCAL_PATH" "$TRACK_REMOTE_REPO_NAME" "$TRACK_REMOTE_REPO_URL"
  fi

  # traverse sync mirror remote repo list
  local MIRROR_INDEX MIRROR_REMOTE_REPO_NAME MIRROR_REMOTE_REPO_URL
  for ((MIRROR_INDEX = 0; MIRROR_INDEX < MIRROR_LENGTH; MIRROR_INDEX++)); do
    # mirror configuration
    MIRROR_REMOTE_REPO_NAME=$(echo "$REPO_DATA" | jq ".mirror[$MIRROR_INDEX].repoName" | tr -d '"')
    MIRROR_REMOTE_REPO_URL=$(echo "$REPO_DATA" | jq ".mirror[$MIRROR_INDEX].repoUrl" | tr -d '"')
    if [[ -z $MIRROR_REMOTE_REPO_NAME ]] || [[ -z $MIRROR_REMOTE_REPO_URL ]]; then
      op_prompt_warn "Mirror repository configuration is not complete, abort this mirror"
      return 0
    fi
    if [[ $EXECUTE_MODE == "init" ]]; then
      op_set_remote_repo "$REPO_NAME" "$REPO_LOCAL_PATH" "$MIRROR_REMOTE_REPO_NAME" "$MIRROR_REMOTE_REPO_URL"
    elif [[ $EXECUTE_MODE == "sync" ]]; then
      op_push_remote_repo "$REPO_NAME" "$REPO_LOCAL_PATH" "$TRACK_REMOTE_REPO_NAME" "$MIRROR_REMOTE_REPO_NAME"
    fi
  done
}
