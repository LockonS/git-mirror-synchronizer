#!/usr/bin/env zsh

# Git operations for git-mirror-synchronizer
# Handles repository cloning, pulling, and syncing to mirror remotes

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
