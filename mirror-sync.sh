#!/usr/bin/env zsh
# shellcheck disable=SC2034

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# configuration
EXECUTE_MODE_OPTION=("init" "sync" "download")
DRY_RUN="false"
DEBUG="false"
SYNC_MIRROR="true"
EXECUTE_MODE="sync"
DOWNLOAD_RETRY=3
DOWNLOAD_RETRY_DELAY=2
DEFAULT_RELEASE_STORAGE="/opt/git/git-release"
DEFAULT_CONFIG_FILE="$SCRIPT_DIR/data/repo.json"
GITHUB_ACCESS_TOKEN_FILE="$SCRIPT_DIR/data/github-access-token"

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
  echo "       -m,--mode        mode      Specify execute mode [init | sync | download], default is 'sync' mode"
  echo "       --sync-mirror    boolean   Specify if mirror repo will be synced, default is true"
  echo "       -h                         Display help page"
}

git_repo_sync_remote_repo() {
  local REPO_NAME REPO_LOCAL_PATH TRACK_REMOTE_REPO_NAME MIRROR_REMOTE_REPO_NAME REPO_BRANCH_NAME
  REPO_NAME="${1}"
  REPO_LOCAL_PATH="${2}"
  TRACK_REMOTE_REPO_NAME="${3}"
  MIRROR_REMOTE_REPO_NAME="${4}"
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

    REPO_URL_MARKER=$(github_repo_extract_name "$REPO_DATA")
    REPO_RELEASE_STORAGE=$(github_repo_extract_storage_path "$REPO_DATA")
    EXCLUDE_KEYWORDS=$(echo "$REPO_DATA" | jq ".excludeKeywords" | tr -d '"')

    # judge if release download is enabled
    if [[ "$REPO_RELEASE_DOWNLOAD" == "true" ]]; then
      github_repo_download_release "$REPO_URL_MARKER" "$REPO_RELEASE_STORAGE" "$EXCLUDE_KEYWORDS"
    else
      op_prompt_debug "This repo is configurated not to download the release artifacts"
    fi

    # judge if tag download is enabled
    if [[ "$REPO_TAG_DOWNLOAD" == "true" ]]; then
      github_repo_download_tag "$REPO_URL_MARKER" "$REPO_RELEASE_STORAGE"
    else
      op_prompt_debug "This repo is configurated not to download the tag artifacts"
    fi

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
    elif [[ $EXECUTE_MODE == "sync" ]]; then
      git_repo_sync_remote_repo "$REPO_NAME" "$REPO_LOCAL_PATH" "$TRACK_REMOTE_REPO_NAME" "$MIRROR_REMOTE_REPO_NAME"
    fi
  done
}

# currently only GitHub is supported
github_repo_extract_name() {
  # parameters
  local REPO_DATA="${1}"

  # configuration variables
  local REPO_URL REPO_AUTHOR REPO_NAME
  REPO_URL=$(echo "$REPO_DATA" | jq ".trackRemoteRepoUrl" | tr -d '"')

  # extract repo creator and name from url
  REPO_AUTHOR=$(echo "$REPO_URL" | awk -F/ '{print $(NF-1)}')
  REPO_NAME=$(basename "$REPO_URL" | sed 's/\.git$//')
  REPO_URL_MARKER="${REPO_AUTHOR}/${REPO_NAME}"
  echo "$REPO_URL_MARKER"
}

# currently only GitHub is supported
github_repo_extract_storage_path() {
  # parameters
  local REPO_DATA="${1}"

  # configuration variables
  local REPO_RELEASE_STORAGE
  REPO_RELEASE_STORAGE=$(echo "$REPO_DATA" | jq ".releaseStoragePath" | tr -d '"')
  if [[ -z "$REPO_RELEASE_STORAGE" ]] || [[ "$REPO_RELEASE_STORAGE" == "null" ]]; then
    REPO_RELEASE_STORAGE="$DEFAULT_RELEASE_STORAGE"
  fi
  echo "$REPO_RELEASE_STORAGE"
}

# currently only GitHub is supported
github_repo_download_release() {
  # parameters
  local REPO_URL_MARKER REPO_RELEASE_STORAGE EXCLUDE_KEYWORDS
  REPO_URL_MARKER="${1}"
  REPO_RELEASE_STORAGE="${2}"
  EXCLUDE_KEYWORDS="${3}"

  # configuration variables
  local REPO_RELEASE_DATA_URL CMD_RETRIEVE_DATA REPO_RELEASE_DATA RELEASE_TAG_NAME RELEASE_STORAGE_PATH
  op_prompt_checkpoint "Downloading release assets for ${NC}${GREEN}${REPO_URL_MARKER}${NC}"

  # assemble release data url
  REPO_RELEASE_DATA_URL="https://api.github.com/repos/${REPO_URL_MARKER}/releases/latest"

  # download release data
  CMD_RETRIEVE_DATA="curl -X GET --retry $DOWNLOAD_RETRY --retry-delay $DOWNLOAD_RETRY_DELAY -H 'Authorization: token $GITHUB_ACCESS_TOKEN' -L -s '$REPO_RELEASE_DATA_URL'"
  REPO_RELEASE_DATA=$(op_run_cmd "$CMD_RETRIEVE_DATA")

  # extract release tag name
  RELEASE_TAG_NAME=$(printf "%s" "$REPO_RELEASE_DATA" | jq '.tag_name' | tr -d '"')

  # print downloading assets message
  # check if the corresponding release was already downloaded
  RELEASE_STORAGE_PATH="${REPO_RELEASE_STORAGE}/${REPO_URL_MARKER}/${RELEASE_TAG_NAME}"

  # traverse release assets list
  local ASSET_INDEX ASSET_LENGTH
  ASSET_LENGTH=$(printf "%s" "$REPO_RELEASE_DATA" | jq '.assets | length')
  if [[ "$ASSET_LENGTH" -eq 0 ]]; then
    op_prompt_msg "No release artifact found"
    return 0
  fi
  op_prompt_msg "Found ${GREEN}${ASSET_LENGTH}${NC} assets"
  for ((ASSET_INDEX = 0; ASSET_INDEX < ASSET_LENGTH; ASSET_INDEX++)); do
    ASSET_DATA=$(printf "%s" "$REPO_RELEASE_DATA" | jq ".assets[$ASSET_INDEX]")
    github_repo_release_asset_download "$RELEASE_STORAGE_PATH" "$ASSET_DATA" "$EXCLUDE_KEYWORDS"
  done
}

# currently only GitHub is supported, only tar.gz archive will be downloaded
github_repo_download_tag() {
  # parameters
  local REPO_URL_MARKER REPO_RELEASE_STORAGE
  REPO_URL_MARKER="${1}"
  REPO_RELEASE_STORAGE="${2}"

  # configuration variables
  local REPO_TAGS_DATA_URL CMD_RETRIEVE_DATA REPO_TAGS_DATA TAG_STORAGE_PATH
  op_prompt_checkpoint "Downloading tags assets for ${NC}${GREEN}${REPO_URL_MARKER}${NC}"

  # assemble release data url
  REPO_TAGS_DATA_URL="https://api.github.com/repos/${REPO_URL_MARKER}/tags"

  # download release data
  CMD_RETRIEVE_DATA="curl -X GET --retry $DOWNLOAD_RETRY --retry-delay $DOWNLOAD_RETRY_DELAY -H 'Authorization: token $GITHUB_ACCESS_TOKEN' -L -s '$REPO_TAGS_DATA_URL'"
  REPO_TAGS_DATA=$(op_run_cmd "$CMD_RETRIEVE_DATA")

  # traverse release assets list
  local ASSET_LENGTH ASSET_DATA ASSET_NAME TAG_NAME TAG_TARBALL_URL CMD_DOWNLOAD_ASSET
  ASSET_LENGTH=$(printf "%s" "$REPO_TAGS_DATA" | jq '. | length')
  if [[ "$ASSET_LENGTH" -eq 0 ]]; then
    op_prompt_msg "No tags artifact found"
    return 0
  fi
  ASSET_DATA=$(printf "%s" "$REPO_TAGS_DATA" | jq ".[0]")

  # extract release tag name
  TAG_NAME=$(printf "%s" "$ASSET_DATA" | jq ".name" | tr -d '"')
  ASSET_NAME="${TAG_NAME}.tar.gz"

  # extract release tag name
  ASSET_DOWNLOAD_URL=$(printf "%s" "$ASSET_DATA" | jq ".tarball_url" | tr -d '"')

  # print downloading assets message
  # check if the corresponding tag resource was already downloaded
  TAG_STORAGE_PATH="${REPO_RELEASE_STORAGE}/${REPO_URL_MARKER}/${TAG_NAME}"
  mkdir -p "$TAG_STORAGE_PATH"

  # skip already downloaded assets
  if [[ -f "${TAG_STORAGE_PATH}/${ASSET_NAME}" ]]; then
    op_prompt_msg "Asset ${BOLD}${GREEN}${ASSET_NAME}${NC} already downloaded"
    return 0
  fi

  CMD_DOWNLOAD_ASSET="curl -L --retry $DOWNLOAD_RETRY --retry-delay $DOWNLOAD_RETRY_DELAY --progress-bar -o '${TAG_STORAGE_PATH}/${ASSET_NAME}' '${ASSET_DOWNLOAD_URL}'"
  op_run_cmd "$CMD_DOWNLOAD_ASSET"

  # remove files if download operation didn't finish successfully
  if [[ "$?" -ne 0 ]]; then
    rm "${TAG_STORAGE_PATH}/${ASSET_NAME}"
  fi
}

github_repo_release_asset_download() {
  # parameters
  local RELEASE_STORAGE_PATH ASSET_DATA EXCLUDE_KEYWORDS
  RELEASE_STORAGE_PATH="${1}"
  ASSET_DATA="${2}"
  EXCLUDE_KEYWORDS="${3}"

  # configuration variables
  local ASSET_NAME ASSET_DOWNLOAD_URL CMD_DOWNLOAD_ASSET
  ASSET_NAME=$(echo "$ASSET_DATA" | jq ".name" | tr -d '"')
  ASSET_DOWNLOAD_URL=$(echo "$ASSET_DATA" | jq ".browser_download_url" | tr -d '"')

  op_prompt_checkpoint "Downloading asset ${BOLD}${GREEN}${ASSET_NAME}${NC}"
  mkdir -p "$RELEASE_STORAGE_PATH"

  # compare exclude keywords
  if [[ -n "$EXCLUDE_KEYWORDS" ]]; then
    IFS=',' read -A EXCLUDE_KEYWORD_LIST <<<"$EXCLUDE_KEYWORDS"
    for KEYWORD in "${EXCLUDE_KEYWORD_LIST[@]}"; do
      if [[ "$ASSET_NAME" =~ $KEYWORD ]]; then
        op_prompt_msg "Asset ${BOLD}${GREEN}${ASSET_NAME}${NC} is configured to be ignored"
        return 0
      fi
    done
  fi

  # skip already downloaded assets
  if [[ -f "${RELEASE_STORAGE_PATH}/${ASSET_NAME}" ]]; then
    op_prompt_msg "Asset ${BOLD}${GREEN}${ASSET_NAME}${NC} already downloaded"
    return 0
  fi

  CMD_DOWNLOAD_ASSET="curl -L --retry $DOWNLOAD_RETRY --retry-delay $DOWNLOAD_RETRY_DELAY --progress-bar -o '${RELEASE_STORAGE_PATH}/${ASSET_NAME}' '${ASSET_DOWNLOAD_URL}'"
  op_run_cmd "$CMD_DOWNLOAD_ASSET"

  # remove files if download operation didn't finish successfully
  if [[ "$?" -ne 0 ]]; then
    rm "${RELEASE_STORAGE_PATH}/${ASSET_NAME}"
  fi
}

git_mirror_entry() {
  local CONFIG_FILE="$DEFAULT_CONFIG_FILE"
  local SINGLE_PROJECT

  while [ $# -gt 0 ]; do
    case ${1} in
      -h | --help) git_mirror_sync_manual && return 0 ;;
      -f | --config-file)
        CONFIG_FILE=${2}
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
      --project)
        SINGLE_PROJECT=${2}
        shift
        shift
        ;;
      --dry-run)
        DRY_RUN="true"
        shift
        ;;
      --debug)
        DEBUG="true"
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
    git_repo_process "$REPO_DATA" "$EXECUTE_MODE" "$SINGLE_PROJECT"
  done
}

git_mirror_prepare() {
  LOG_FILE='/var/log/mirror-sync.log'
  EXECUTE_TIME=$(date '+%Y-%m-%d %H:%M:%S')
  if [[ ! -f $LOG_FILE ]]; then
    touch $LOG_FILE
  fi
  if [[ -f "$GITHUB_ACCESS_TOKEN_FILE" ]]; then
    GITHUB_ACCESS_TOKEN=$(cat "$GITHUB_ACCESS_TOKEN_FILE")
  fi
  export GITHUB_ACCESS_TOKEN
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
  if [[ "$DEBUG" == true ]] || [[ "$DRY_RUN" == true ]]; then
    echo -e "\n${GREY}${CMD_STR}${NC}\n"
  fi
  if [[ "$DRY_RUN" != true ]]; then
    if ! zsh -c "$CMD_STR"; then
      op_prompt_error "Error: command execute failure"
      return 1
    fi
  fi
}

git_mirror_prepare
git_mirror_entry "$@"
