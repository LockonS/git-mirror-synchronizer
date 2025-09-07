#!/usr/bin/env zsh

# function and variables in this file is github exclusive
export GITHUB_ACCESS_TOKEN_FILE="$DATA_PATH/github/github-access-token"
export GITHUB_ACCESS_TOKEN

op_load_github_access_token() {
  if [[ -f "$GITHUB_ACCESS_TOKEN_FILE" ]]; then
    GITHUB_ACCESS_TOKEN=$(cat "$GITHUB_ACCESS_TOKEN_FILE")
  fi
}
op_load_github_access_token

# extract repo name from repo data
op_github_extract_repo_identifier() {
  local REPO_URL="${1}"

  # extract repo creator and name from url
  REPO_AUTHOR=$(echo "$REPO_URL" | awk -F/ '{print $(NF-1)}')
  REPO_NAME=$(basename "$REPO_URL" | sed 's/\.git$//')
  REPO_IDENTIFIER="${REPO_AUTHOR}/${REPO_NAME}"
  echo "$REPO_IDENTIFIER"
}

# currently only GitHub is supported
op_github_download_release() {
  # parameters
  local REPO_URL REPO_IDENTIFIER REPO_RELEASE_STORAGE EXCLUDE_KEYWORDS
  REPO_URL="${1}"
  REPO_RELEASE_STORAGE="${2}"
  EXCLUDE_KEYWORDS="${3}"
  REPO_IDENTIFIER=$(op_github_extract_repo_identifier "$REPO_URL")

  # configuration variables
  local REPO_RELEASE_DATA_URL CMD_RETRIEVE_DATA REPO_RELEASE_DATA RELEASE_TAG_NAME RELEASE_STORAGE_PATH
  op_prompt_checkpoint "Downloading release assets for ${NC}${GREEN}${REPO_IDENTIFIER}${NC}"

  # assemble release data url
  REPO_RELEASE_DATA_URL="https://api.github.com/repos/${REPO_IDENTIFIER}/releases/latest"

  # download release data
  CMD_RETRIEVE_DATA="curl -X GET --retry $DOWNLOAD_RETRY --retry-delay $DOWNLOAD_RETRY_DELAY -H 'Authorization: token $GITHUB_ACCESS_TOKEN' -L -s '$REPO_RELEASE_DATA_URL'"
  REPO_RELEASE_DATA=$(op_run_cmd "$CMD_RETRIEVE_DATA")

  # extract release tag name
  RELEASE_TAG_NAME=$(printf "%s" "$REPO_RELEASE_DATA" | jq '.tag_name' | tr -d '"')

  # print downloading assets message
  # check if the corresponding release was already downloaded
  RELEASE_STORAGE_PATH="${REPO_RELEASE_STORAGE}/${REPO_IDENTIFIER}/${RELEASE_TAG_NAME}"

  # traverse release assets list
  local ASSET_INDEX ASSET_LENGTH
  ASSET_LENGTH=$(printf "%s" "$REPO_RELEASE_DATA" | jq '.assets | length')
  if [[ "$ASSET_LENGTH" -eq 0 ]]; then
    op_prompt_info "No release artifact found"
    return 0
  fi
  op_prompt_info "Found ${GREEN}${ASSET_LENGTH}${NC} assets"
  for ((ASSET_INDEX = 0; ASSET_INDEX < ASSET_LENGTH; ASSET_INDEX++)); do
    ASSET_DATA=$(printf "%s" "$REPO_RELEASE_DATA" | jq ".assets[$ASSET_INDEX]")
    op_github_download_release_asset "$RELEASE_STORAGE_PATH" "$ASSET_DATA" "$EXCLUDE_KEYWORDS"
  done
}

# currently only GitHub is supported, only tar.gz archive will be downloaded
op_github_download_tag() {
  # parameters
  local REPO_URL REPO_RELEASE_STORAGE REPO_IDENTIFIER
  REPO_URL="${1}"
  REPO_RELEASE_STORAGE="${2}"
  REPO_IDENTIFIER=$(op_github_extract_repo_identifier "$REPO_URL")

  # configuration variables
  local REPO_TAGS_DATA_URL CMD_RETRIEVE_DATA REPO_TAGS_DATA TAG_STORAGE_PATH
  op_prompt_checkpoint "Downloading tags assets for ${NC}${GREEN}${REPO_IDENTIFIER}${NC}"

  # assemble release data url
  REPO_TAGS_DATA_URL="https://api.github.com/repos/${REPO_IDENTIFIER}/tags"

  # download release data
  CMD_RETRIEVE_DATA="curl -X GET --retry $DOWNLOAD_RETRY --retry-delay $DOWNLOAD_RETRY_DELAY -H 'Authorization: token $GITHUB_ACCESS_TOKEN' -L -s '$REPO_TAGS_DATA_URL'"
  REPO_TAGS_DATA=$(op_run_cmd "$CMD_RETRIEVE_DATA")

  # traverse release assets list
  local ASSET_LENGTH ASSET_DATA ASSET_NAME TAG_NAME CMD_DOWNLOAD_ASSET
  ASSET_LENGTH=$(printf "%s" "$REPO_TAGS_DATA" | jq '. | length')
  if [[ "$ASSET_LENGTH" -eq 0 ]]; then
    op_prompt_info "No tags artifact found"
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
  TAG_STORAGE_PATH="${REPO_RELEASE_STORAGE}/${REPO_IDENTIFIER}/${TAG_NAME}"
  mkdir -p "$TAG_STORAGE_PATH"

  # skip already downloaded assets
  if [[ -f "${TAG_STORAGE_PATH}/${ASSET_NAME}" ]]; then
    op_prompt_info "Asset ${BOLD}${GREEN}${ASSET_NAME}${NC} already downloaded"
    return 0
  fi

  CMD_DOWNLOAD_ASSET="curl -L --retry $DOWNLOAD_RETRY --retry-delay $DOWNLOAD_RETRY_DELAY --progress-bar -o '${TAG_STORAGE_PATH}/${ASSET_NAME}' '${ASSET_DOWNLOAD_URL}'"
  op_run_cmd "$CMD_DOWNLOAD_ASSET"

  # remove files if download operation didn't finish successfully
  if [[ "$?" -ne 0 ]]; then
    rm "${TAG_STORAGE_PATH}/${ASSET_NAME}"
  fi
}

op_github_download_release_asset() {
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
        op_prompt_info "Asset ${BOLD}${GREEN}${ASSET_NAME}${NC} is configured to be ignored"
        return 0
      fi
    done
  fi

  # skip already downloaded assets
  if [[ -f "${RELEASE_STORAGE_PATH}/${ASSET_NAME}" ]]; then
    op_prompt_info "Asset ${BOLD}${GREEN}${ASSET_NAME}${NC} already downloaded"
    return 0
  fi

  CMD_DOWNLOAD_ASSET="curl -L --retry $DOWNLOAD_RETRY --retry-delay $DOWNLOAD_RETRY_DELAY --progress-bar -o '${RELEASE_STORAGE_PATH}/${ASSET_NAME}' '${ASSET_DOWNLOAD_URL}'"
  op_run_cmd "$CMD_DOWNLOAD_ASSET"

  # remove files if download operation didn't finish successfully
  if [[ "$?" -ne 0 ]]; then
    rm "${RELEASE_STORAGE_PATH}/${ASSET_NAME}"
  fi
}
