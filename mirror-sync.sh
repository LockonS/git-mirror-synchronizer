#!/usr/bin/env zsh
# shellcheck disable=SC2034

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# configuration
EXECUTE_MODE_OPTION=("init" "sync")
DRY_RUN="false"
SYNC_MIRROR="true"
DOWNLOAD_RELEASE="false"
EXECUTE_MODE="sync"
DEFAULT_RELEASE_STORAGE="/data/storage/git-release"
DEFAULT_CONFIG_FILE="$SCRIPT_DIR/data/repo.json"

# color
BLACK=$(tput setaf 0)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)
GREY=$(tput setaf 250)
DEFAULT=$(tput op)
NC=$(tput sgr0)
BOLD=$(tput bold)

git_mirror_sync_manual() {
  echo "usage: mirror-sync.sh [-f|--config-file file] [-m|--mode mode] [--sync-mirror boolean] [-h|--help]"
  echo "       -f,--config-file file      Specify input config file, default to path-to-script/data/repo.json"
  echo "       -m,--mode        mode      Specify execute mode [init | sync], default is 'sync' mode"
  echo "       --sync-mirror    boolean   Specify if mirror repo will be synced, default is true"
  echo "       -h                         Display help page"
}

git_repo_sync_remote_repo() {
  local REPO_NAME REPO_LOCAL_PATH TRACK_REMOTE_REPO_NAME MIRROR_REMOTE_REPO_NAME REPO_BRANCH_NAME
  REPO_NAME=${1}
  REPO_LOCAL_PATH=${2}
  TRACK_REMOTE_REPO_NAME=${3}
  MIRROR_REMOTE_REPO_NAME=${4}
  REPO_BRANCH_NAME=$(git -C "$REPO_LOCAL_PATH" rev-parse --abbrev-ref HEAD)

  # print repo sync message
  op_prompt_checkpoint "Synchronize project ${BOLD}${GREEN}${REPO_NAME}${NC} to remote repo ${BOLD}${BLUE}${MIRROR_REMOTE_REPO_NAME}${NC}"
  echo -e "Project path: ${BOLD}${REPO_LOCAL_PATH}${NC}"
  echo -e "Tracking branch: ${BLUE}${REPO_BRANCH_NAME}${NC}"

  # assemble git operate command
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

git_repo_init_local_repo() {
  local REPO_NAME REPO_LOCAL_PATH TRACK_REMOTE_REPO_NAME TRACK_REMOTE_REPO_URL
  REPO_NAME=${1}
  REPO_LOCAL_PATH=${2}
  TRACK_REMOTE_REPO_NAME=${3}
  TRACK_REMOTE_REPO_URL=${4}

  # print repo init message
  op_prompt_checkpoint "Initialize project ${BOLD}${GREEN}${REPO_NAME}${NC} to local path ${BOLD}${BLUE}${REPO_LOCAL_PATH}${NC}"
  mkdir -p "$(dirname "$REPO_LOCAL_PATH")"

  # validate if local repo is properly initalized
  if [[ -d $REPO_LOCAL_PATH/.git ]]; then
    op_prompt_debug "Project repository is initialized, abort clone process"
    return 0
  fi

  # assemble git clone command
  local CMD_GIT_CLONE_REPO="git clone $TRACK_REMOTE_REPO_URL $REPO_LOCAL_PATH"
  op_run_cmd "$CMD_GIT_CLONE_REPO"
}

git_repo_set_remote_repo() {
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

git_repo_process() {
  # parameters
  local REPO_DATA EXECUTE_MODE
  REPO_DATA=${1}
  EXECUTE_MODE=${2}

  # configuration variables
  local REPO_NAME REPO_LOCAL_PATH TRACK_REMOTE_REPO_NAME TRACK_REMOTE_REPO_URL MIRROR_LENGTH
  REPO_NAME=$(echo "$REPO_DATA" | jq '.repoName' | tr -d '"')
  REPO_NAME=$(echo "$REPO_DATA" | jq '.repoName' | tr -d '"')
  REPO_LOCAL_PATH=$(echo "$REPO_DATA" | jq '.repoLocalPath' | tr -d '"')
  TRACK_REMOTE_REPO_NAME=$(echo "$REPO_DATA" | jq '.trackRemoteRepoName' | tr -d '"')
  TRACK_REMOTE_REPO_URL=$(echo "$REPO_DATA" | jq '.trackRemoteRepoUrl' | tr -d '"')
  MIRROR_LENGTH=$(echo "$REPO_DATA" | jq '.mirror | length')

  # validate configuration of tracking remote repo
  if [[ -z $REPO_LOCAL_PATH ]] || [[ -z $TRACK_REMOTE_REPO_NAME ]] || [[ -z $TRACK_REMOTE_REPO_URL ]]; then
    op_prompt_warn "Tracking repository configuration is not complete, abort task"
    return 0
  fi

  # initialize local repo
  if [[ $EXECUTE_MODE == "init" ]]; then
    git_repo_init_local_repo "$REPO_NAME" "$REPO_LOCAL_PATH" "$TRACK_REMOTE_REPO_NAME" "$TRACK_REMOTE_REPO_URL"
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
      git_repo_set_remote_repo "$REPO_NAME" "$REPO_LOCAL_PATH" "$MIRROR_REMOTE_REPO_NAME" "$MIRROR_REMOTE_REPO_URL"
    else
      git_repo_sync_remote_repo "$REPO_NAME" "$REPO_LOCAL_PATH" "$TRACK_REMOTE_REPO_NAME" "$MIRROR_REMOTE_REPO_NAME"
    fi
  done

  # if download release option is configured
  local REPO_RELEASE_DOWNLOAD
  if [[ "$DOWNLOAD_RELEASE" == true ]]; then
    REPO_RELEASE_DOWNLOAD=$(echo "$REPO_DATA" | jq ".downloadRelease" | tr -d '"')
    if [[ "$REPO_RELEASE_DOWNLOAD" != "true" ]]; then
      op_prompt_debug "This repo is configurated not to download the release artifacts"
      return 0
    fi
    git_repo_download_release "$REPO_DATA"
  fi
}

# currently only GitHub is supported
git_repo_download_release() {
  # parameters
  local REPO_DATA=${1}

  # configuration variables
  local REPO_URL REPO_RELEASE_STORAGE REPO_IDENTIFIER REPO_AUTHOR REPO_NAME REPO_RELEASE_DATA_URL REPO_RELEASE_DATA RELEASE_TAG_NAME RELEASE_STORAGE_PATH
  REPO_URL=$(echo "$REPO_DATA" | jq ".trackRemoteRepoUrl" | tr -d '"')
  REPO_RELEASE_STORAGE=$(echo "$REPO_DATA" | jq ".releaseStoragePath" | tr -d '"')
  if [[ -z "$REPO_RELEASE_STORAGE" ]] || [[ "$REPO_RELEASE_STORAGE" == "null" ]]; then
    REPO_RELEASE_STORAGE="$DEFAULT_RELEASE_STORAGE"
  fi

  # extract repo creator and name from url
  REPO_IDENTIFIER=$(git_repo_extract_identifier "$REPO_URL" "github.com")
  REPO_AUTHOR=$(echo "$REPO_IDENTIFIER" | awk -F'[/:]' '{print $2}')
  REPO_NAME=$(echo "$REPO_IDENTIFIER" | awk -F'[/:]' '{print $3}' | sed 's/\.git$//')

  # assemble release data url
  REPO_RELEASE_DATA_URL="https://api.github.com/repos/${REPO_AUTHOR}/${REPO_NAME}/releases/latest"

  # download release data
  REPO_RELEASE_DATA=$(curl -X GET -L -s "$REPO_RELEASE_DATA_URL")

  # extract release tag name
  RELEASE_TAG_NAME=$(echo "$REPO_RELEASE_DATA" | jq '.name' | tr -d '"')

  # print downloading assets message
  # check if the corresponding release was already downloaded
  RELEASE_STORAGE_PATH="${REPO_RELEASE_STORAGE}/${REPO_AUTHOR}/${REPO_NAME}/${RELEASE_TAG_NAME}"
  if [[ -d "$RELEASE_STORAGE_PATH" ]]; then
    op_prompt_warn "Release $RELEASE_TAG_NAME already downloaded, skip"
    return 0
  fi

  # traverse release assets list
  local ASSET_INDEX ASSET_LENGTH
  ASSET_LENGTH=$(echo "$REPO_RELEASE_DATA" | jq '.assets | length')
  op_prompt_checkpoint "Downloading ${ASSET_LENGTH} assets for ${REPO_AUTHOR}/${REPO_NAME}"
  for ((ASSET_INDEX = 0; ASSET_INDEX < ASSET_LENGTH; ASSET_INDEX++)); do
    ASSET_DATA=$(echo "$REPO_RELEASE_DATA" | jq ".assets[$ASSET_INDEX]")
    git_repo_release_asset_download "$RELEASE_STORAGE_PATH" "$ASSET_DATA"
  done
}

git_repo_extract_identifier() {
  local REPO_URL DELIMITER_STR
  REPO_URL=${1}
  DELIMITER_STR=${2}
  echo "$REPO_URL" | sed "s/${DELIMITER_STR}/\n/g" | sed -n '2p'
}

git_repo_release_asset_download() {
  # parameters
  local RELEASE_STORAGE_PATH ASSET_DATA
  RELEASE_STORAGE_PATH="${1}"
  ASSET_DATA="${2}"

  # configuration variables
  local ASSET_NAME ASSET_DOWNLOAD_URL CMD_DOWNLOAD_ASSET
  ASSET_NAME=$(echo "$ASSET_DATA" | jq ".name" | tr -d '"')
  ASSET_DOWNLOAD_URL=$(echo "$ASSET_DATA" | jq ".browser_download_url" | tr -d '"')

  op_prompt_checkpoint "Downloading asset ${BOLD}${GREEN}${ASSET_NAME}${NC}"
  mkdir -p "$RELEASE_STORAGE_PATH"
  CMD_DOWNLOAD_ASSET="curl -L --progress-bar -o '${RELEASE_STORAGE_PATH}/${ASSET_NAME}' '${ASSET_DOWNLOAD_URL}'"
  op_run_cmd "$CMD_DOWNLOAD_ASSET"
}

git_mirror_entry() {
  local CONFIG_FILE="$DEFAULT_CONFIG_FILE"

  while [ $# -gt 0 ]; do
    case ${1} in
    -h | --help) git_mirror_sync_manual && return 0 ;;
    -f | --config-file)
      CONFIG_FILE=${2:-"$DEFAULT_CONFIG_FILE"}
      shift
      shift
      ;;
    -m | --mode)
      EXECUTE_MODE=${2}
      shift
      shift
      ;;
    --sync-mirror)
      SYNC_MIRROR=${2}
      shift
      shift
      ;;
    --download-release)
      DOWNLOAD_RELEASE=${2}
      shift
      shift
      ;;
    *) shift ;;
    esac
  done

  # check if config file exist
  [[ ! -f $CONFIG_FILE ]] && echo "Config file ${YELLOW}$CONFIG_FILE${NC} does not exist" && return 1

  if [[ -z "$EXECUTE_MODE" ]]; then
    op_prompt_error "Error: execution mode could not be empty"
    git_mirror_sync_manual
    exit 1
  fi

  if [[ ! "${EXECUTE_MODE_OPTION[*]}" =~ $EXECUTE_MODE ]]; then
    op_prompt_error "Error: execution mode '$EXECUTE_MODE' not exist"
    git_mirror_sync_manual
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
    git_repo_process "$REPO_DATA" "$EXECUTE_MODE"
  done
}

git_mirror_prepare() {
  LOG_FILE='/var/log/mirror-sync.log'
  EXECUTE_TIME=$(date '+%Y-%m-%d %H:%M:%S')
  if [[ ! -f $LOG_FILE ]]; then
    touch $LOG_FILE
  fi
  echo -e "\n\n--------------- $EXECUTE_TIME ---------------\n"
}

op_prompt_checkpoint() {
  echo -e "${BLUE}==>${NC} ${BOLD}${WHITE}${1}${NC}"
}

op_prompt_msg() {
  echo -e "${WHITE}${1}${NC}"
}

op_prompt_error() {
  echo -e "${BOLD}${RED}${1}${NC}"
}

op_prompt_warn() {
  echo -e "${BOLD}${YELLOW}${1}${NC}"
}

op_prompt_debug() {
  if [[ "$DEBUG" == true ]]; then
    echo -e "${GREY}${YELLOW}${1}${NC}"
  fi
}

op_run_cmd() {
  local CMD_STR=${*}
  if [[ "$DEBUG" == true ]]; then
    echo -e "\n${GREY}${CMD_STR}${NC}\n"
  fi
  if [[ "$DRY_RUN" != true ]]; then
    if ! zsh -c "$CMD_STR"; then
      op_prompt_error "Error: command execute failure"
    fi
  fi
}

op_run_cmd_with_result() {
  local CMD_STR=${*}
  if [[ "$DEBUG" == true ]]; then
    echo -e "\n${GREY}${CMD_STR}${NC}\n"
  fi
  if [[ "$DRY_RUN" != true ]]; then
    VAR_CMD_EXEC_STDOUT=$(zsh -c "$CMD_STR")
    export VAR_CMD_EXEC_STDOUT
  fi
}

git_mirror_prepare
git_mirror_entry "$@"

# TODO
#  1. optimize the workmode and flow, do refactor
#  2. update the prompt message
#  3. add modification to script for release download support for other platforms
