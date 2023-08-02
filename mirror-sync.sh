#!/usr/bin/env zsh

SCRIPT_DIR=$(dirname "$0")
INDENT=" --"
DEBUG=false
LOG_FILE='/var/log/mirror-sync.log'
EXECUTE_TIME=$(date '+%Y-%m-%d %H:%M:%S')

# color
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[1;31m'
NC='\033[0m'

repo-sync() {
  local REPO_NAME REPO_LOCAL_PATH TRACK_REMOTE_REPO_NAME MIRROR_REMOTE_REPO_NAME DRY_RUN
  REPO_NAME=${1}
  REPO_LOCAL_PATH=${2}
  TRACK_REMOTE_REPO_NAME=${3}
  MIRROR_REMOTE_REPO_NAME=${4}
  DRY_RUN=${5}
  echo -e "Sync project ==> ${GREEN}$REPO_NAME${NC} to ${BLUE}$MIRROR_REMOTE_REPO_NAME${NC}"
  if [[ $DRY_RUN == true ]]; then
    echo "git -C $REPO_LOCAL_PATH pull $TRACK_REMOTE_REPO_NAME && git -C $REPO_LOCAL_PATH push $MIRROR_REMOTE_REPO_NAME"
    return 0
  fi
  git -C "$REPO_LOCAL_PATH" pull "$TRACK_REMOTE_REPO_NAME" && git -C "$REPO_LOCAL_PATH" push "$MIRROR_REMOTE_REPO_NAME"
  echo ""
}

repo-init() {
  local REPO_NAME REPO_LOCAL_PATH TRACK_REMOTE_REPO_NAME TRACK_REMOTE_REPO_URL DRY_RUN
  REPO_NAME=${1}
  REPO_LOCAL_PATH=${2}
  TRACK_REMOTE_REPO_NAME=${3}
  TRACK_REMOTE_REPO_URL=${4}
  DRY_RUN=${5}
  echo -e "Initialize project ==> ${GREEN}$REPO_NAME${NC}	${BLUE}$REPO_LOCAL_PATH${NC}"
  mkdir -p "$(dirname "$REPO_LOCAL_PATH")"
  if [[ -d $REPO_LOCAL_PATH/.git ]]; then
    [[ $DEBUG == true ]] && echo "${INDENT} ${YELLOW}Project repository is initialized, abort clone process${NC}"
    return 0
  fi
  [[ $DRY_RUN == true ]] && echo "git clone $TRACK_REMOTE_REPO_URL $REPO_LOCAL_PATH" && return 0
  git clone "$TRACK_REMOTE_REPO_URL" "$REPO_LOCAL_PATH"
  echo ""
}

repo-set-remote-repo() {
  local REPO_NAME MIRROR_REMOTE_REPO_NAME MIRROR_REMOTE_REPO_URL DRY_RUN
  REPO_NAME=${1}
  REPO_LOCAL_PATH=${2}
  MIRROR_REMOTE_REPO_NAME=${3}
  MIRROR_REMOTE_REPO_URL=${4}
  DRY_RUN=${5}
  cd "$REPO_LOCAL_PATH"
  # check if remote repo has been configured already
  if ! git remote | grep -q "^$MIRROR_REMOTE_REPO_NAME$"; then
    echo -e "${INDENT} Add remote repository ==> ${GREEN}$MIRROR_REMOTE_REPO_NAME${NC}	${BLUE}$MIRROR_REMOTE_REPO_URL${NC}"
    [[ $DRY_RUN == true ]] && echo "git remote add $MIRROR_REMOTE_REPO_NAME $MIRROR_REMOTE_REPO_URL" && return 0
    git remote add "$MIRROR_REMOTE_REPO_NAME" "$MIRROR_REMOTE_REPO_URL"
  else
    echo -e "${INDENT} Remote repository configured ==> ${GREEN}$MIRROR_REMOTE_REPO_NAME${NC}	${BLUE}$MIRROR_REMOTE_REPO_URL${NC}"
  fi
}

repo-parse() {
  local REPO_DATA EXECUTE_MODE REPO_NAME REPO_LOCAL_PATH TRACK_REMOTE_REPO_NAME TRACK_REMOTE_REPO_URL MIRROR_LENGTH
  REPO_DATA=${1}
  EXECUTE_MODE=${2}
  REPO_NAME=$(echo "$REPO_DATA" | jq '.repoName' | tr -d '"')
  REPO_LOCAL_PATH=$(echo "$REPO_DATA" | jq '.repoLocalPath' | tr -d '"')
  TRACK_REMOTE_REPO_NAME=$(echo "$REPO_DATA" | jq '.trackRemoteRepoName' | tr -d '"')
  TRACK_REMOTE_REPO_URL=$(echo "$REPO_DATA" | jq '.trackRemoteRepoUrl' | tr -d '"')
  MIRROR_LENGTH=$(echo "$REPO_DATA" | jq '.mirror | length')
  if [[ -z $REPO_LOCAL_PATH ]] || [[ -z $TRACK_REMOTE_REPO_NAME ]] || [[ -z $TRACK_REMOTE_REPO_URL ]]; then
    [[ $DEBUG == true ]] && echo "${INDENT} ${YELLOW}Tracking repository configuration is not complete, abort task${NC}"
    return 0
  fi
  # traverse miror list
  [[ $EXECUTE_MODE == "init" ]] && repo-init "$REPO_NAME" "$REPO_LOCAL_PATH" "$TRACK_REMOTE_REPO_NAME" "$TRACK_REMOTE_REPO_URL"
  local MIRROR_REMOTE_REPO_NAME MIRROR_REMOTE_REPO_URL
  for ((MIRROR_INDEX = 0; MIRROR_INDEX < MIRROR_LENGTH; MIRROR_INDEX++)); do
    MIRROR_REMOTE_REPO_NAME=$(echo "$REPO_DATA" | jq ".mirror[$MIRROR_INDEX].repoName" | tr -d '"')
    MIRROR_REMOTE_REPO_URL=$(echo "$REPO_DATA" | jq ".mirror[$MIRROR_INDEX].repoUrl" | tr -d '"')
    if [[ -z $MIRROR_REMOTE_REPO_NAME ]] || [[ -z $MIRROR_REMOTE_REPO_URL ]]; then
      [[ $DEBUG == true ]] && echo "${INDENT} ${YELLOW}Mirror repository configuration is not complete, abort task${NC}"
      return 0
    fi
    if [[ $EXECUTE_MODE == "init" ]]; then
      repo-set-remote-repo "$REPO_NAME" "$REPO_LOCAL_PATH" "$MIRROR_REMOTE_REPO_NAME" "$MIRROR_REMOTE_REPO_URL"
    else
      repo-sync "$REPO_NAME" "$REPO_LOCAL_PATH" "$TRACK_REMOTE_REPO_NAME" "$MIRROR_REMOTE_REPO_NAME"
    fi
  done
}

help-page() {
  echo "usage: mirror-sync.sh [-f|--config-file file] [-m|--mode mode] [-h|--help]"
  echo "       -f,--config-file  file   Specify input config file, default to path-to-script/data/repo.json"
  echo "       -m,--mode   mode         Specify execute mode [init | sync], default to sync mode"
  echo "       -h                       Display help page"
}

running-check() {
  [[ ! -f $LOG_FILE ]] && touch $LOG_FILE
  echo -e "\n\n--------------- $EXECUTE_TIME ---------------\n"
}

load-config() {
  local EXECUTE_MODE CONFIG_FILE DEBUG
  EXECUTE_MODE='sync'
  CONFIG_FILE=$SCRIPT_DIR/data/repo.json

  while [ $# -gt 0 ]; do
    case ${1} in
      -h | --help) help-page && return 0 ;;
      -f | --config-file) CONFIG_FILE=${2} && shift 2 ;;
      -m | --mode) EXECUTE_MODE=${2} && shift 2 ;;
      -d | --debug) DEBUG=true && shift 1 ;;
      *) shift 1 ;;
    esac
  done

  # check if config file exist
  [[ ! -f $CONFIG_FILE ]] && echo "Config file ${YELLOW}$CONFIG_FILE${NC} does not exist" && return 1
  # validate execute mode
  if [[ $EXECUTE_MODE != 'init' ]] && [[ $EXECUTE_MODE != 'sync' ]]; then
    echo -e "Execute mode ${YELLOW}$EXECUTE_MODE${NC} not exist"
    return 1
  fi

  local CONFIG_CONTENT REPO_LENGTH REPO_DATA PROGRESS_INDEX
  # get config file content
  CONFIG_CONTENT=$(cat "$CONFIG_FILE")
  # traverse repo list
  REPO_LENGTH=$(echo "$CONFIG_CONTENT" | jq '. | length')
  for ((REPO_INDEX = 0; REPO_INDEX < REPO_LENGTH; REPO_INDEX++)); do
    REPO_DATA=$(echo "$CONFIG_CONTENT" | jq ".[$REPO_INDEX]")
    PROGRESS_INDEX=$((REPO_INDEX + 1))
    echo -e "\n--------------- Progress $PROGRESS_INDEX/$REPO_LENGTH ---------------\n"
    repo-parse "$REPO_DATA" "$EXECUTE_MODE"
  done
}

running-check
load-config "$@"
