#!/usr/bin/env zsh

# function and variables in this file is github exclusive
export GITHUB_ACCESS_TOKEN_FILE="$DATA_PATH/github/github-access-token"
export GITHUB_ACCESS_TOKEN

op_load_github_access_token() {
  op_load_access_token "$GITHUB_ACCESS_TOKEN_FILE" GITHUB_ACCESS_TOKEN "GitHub"
}

# extract repo name from repo data
op_github_extract_repo_identifier() {
  local REPO_URL REPO_AUTHOR REPO_NAME REPO_IDENTIFIER
  REPO_URL="${1}"

  # extract repo creator and name from url
  REPO_AUTHOR=$(echo "$REPO_URL" | awk -F/ '{print $(NF-1)}')
  REPO_NAME=$(basename "$REPO_URL" | sed 's/\.git$//')
  REPO_IDENTIFIER="${REPO_AUTHOR}/${REPO_NAME}"
  echo "$REPO_IDENTIFIER"
}

# check GitHub API response for errors
# Parameters: JSON_DATA, ARTIFACT_TYPE ("release" or "tags")
# Returns: 0 if no error, 1 for errors, 2 for "Not Found" (caller should exit gracefully)
op_github_check_api_response() {
  local JSON_DATA ARTIFACT_TYPE RESPONSE_MESSAGE
  JSON_DATA="${1}"
  ARTIFACT_TYPE="${2}"
  
  RESPONSE_MESSAGE=$(printf "%s" "$JSON_DATA" | jq -r 'select(type=="object" and has("message")) | .message')
  if [[ -n "$RESPONSE_MESSAGE" && "$RESPONSE_MESSAGE" != "null" ]]; then
    case "$RESPONSE_MESSAGE" in
      *"Not Found"*)
        op_prompt_info "No ${ARTIFACT_TYPE} artifact found"
        return 2
        ;;
      *)
        op_prompt_warn "GitHub API response: ${BOLD}${RESPONSE_MESSAGE}${NC}"
        return 1
        ;;
    esac
  fi
  return 0
}

# validate GitHub API response and handle status codes
# Parameters: JSON_DATA, ARTIFACT_TYPE ("release" or "tags")
# Returns: 0 for success (continue), 200 for "Not Found" (parent should return 0), other codes for errors
op_github_validate_response() {
  local JSON_DATA ARTIFACT_TYPE
  JSON_DATA="${1}"
  ARTIFACT_TYPE="${2}"

  echo "before op_github_check_api_response"
  
  op_github_check_api_response "$JSON_DATA" "$ARTIFACT_TYPE"
  local API_STATUS=$?
  
  if [[ $API_STATUS -eq 2 ]]; then
    # Not Found - parent should return 0 gracefully
    return 200
  elif [[ $API_STATUS -ne 0 ]]; then
    # Error - parent should return this code
    return $API_STATUS
  fi
  
  # Success - continue processing
  return 0
}

op_github_download_release() {
  local REPO_URL REPO_IDENTIFIER REPO_RELEASE_STORAGE EXCLUDE_KEYWORDS CUSTOM_IDENTIFIER KEPT_VERSION_NUM REPO_CATALOG AUTH_REQUEST_HEADER KEPT_VERSIONS
  REPO_URL="${1}"
  REPO_RELEASE_STORAGE="${2}"
  EXCLUDE_KEYWORDS="${3}"
  CUSTOM_IDENTIFIER="${4}"
  KEPT_VERSION_NUM="${5}"
  REPO_CATALOG="${6}"
  KEPT_VERSIONS="${7}"
  
  # use custom identifier if provided, otherwise extract from URL
  if [[ -n "$CUSTOM_IDENTIFIER" ]] && [[ "$CUSTOM_IDENTIFIER" != "null" ]]; then
    REPO_IDENTIFIER="$CUSTOM_IDENTIFIER"
  else
    REPO_IDENTIFIER=$(op_github_extract_repo_identifier "$REPO_URL")
  fi

  # configuration variables
  local REPO_RELEASE_DATA_URL CMD_RETRIEVE_DATA REPO_RELEASE_DATA RELEASE_TAG_NAME RELEASE_STORAGE_PATH
  echo -e ""
  op_prompt_checkpoint "Downloading release assets for ${BOLD}${GREEN}${REPO_IDENTIFIER}${NC}"

  # assemble release data url
  REPO_RELEASE_DATA_URL="https://api.github.com/repos/${REPO_IDENTIFIER}/releases/latest"

  # assemble auth header if access token is available
  if [[ -n "$GITHUB_ACCESS_TOKEN" ]];then
    AUTH_REQUEST_HEADER="-H 'Authorization: token $GITHUB_ACCESS_TOKEN'"
  fi

  # download release data
  CMD_RETRIEVE_DATA="curl -X GET --retry $DOWNLOAD_RETRY --retry-delay $DOWNLOAD_RETRY_DELAY $AUTH_REQUEST_HEADER -L -s '$REPO_RELEASE_DATA_URL'"
  
  op_prompt_debug "${CMD_RETRIEVE_DATA}"
  
  op_run_cmd_with_result "$CMD_RETRIEVE_DATA"
  REPO_RELEASE_DATA="$CMD_EXEC_STDOUT"

  echo "CMD_EXEC_STDOUT: $CMD_EXEC_STDOUT"

  # Check for error message in response (e.g., rate limit or not found)
  op_github_validate_response "$REPO_RELEASE_DATA" "release"
  local RET=$?
  if [[ $RET -eq 200 ]]; then return 0; elif [[ $RET -ne 0 ]]; then return $RET; fi

  # extract release tag name
  RELEASE_TAG_NAME=$(printf "%s" "$REPO_RELEASE_DATA" | jq '.tag_name' | tr -d '"')

  # print downloading assets message
  # check if the corresponding release was already downloaded
  # include catalog in storage path
  if [[ -n "$REPO_CATALOG" ]] && [[ "$REPO_CATALOG" != "null" ]]; then
    RELEASE_STORAGE_PATH="${REPO_RELEASE_STORAGE}/${REPO_CATALOG}/${REPO_IDENTIFIER}/${RELEASE_TAG_NAME}"
  else
    RELEASE_STORAGE_PATH="${REPO_RELEASE_STORAGE}/${REPO_IDENTIFIER}/${RELEASE_TAG_NAME}"
  fi

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

  # cleanup old releases (include catalog in base path)
  if [[ -n "$REPO_CATALOG" ]] && [[ "$REPO_CATALOG" != "null" ]]; then
    op_cleanup_old_versions "${REPO_RELEASE_STORAGE}/${REPO_CATALOG}" "$REPO_IDENTIFIER" "$KEPT_VERSION_NUM" "release" "$KEPT_VERSIONS"
  else
    op_cleanup_old_versions "$REPO_RELEASE_STORAGE" "$REPO_IDENTIFIER" "$KEPT_VERSION_NUM" "release" "$KEPT_VERSIONS"
  fi
}

# currently only GitHub is supported, only tar.gz archive will be downloaded
op_github_download_tag() {
  # parameters
  local REPO_URL REPO_RELEASE_STORAGE REPO_IDENTIFIER CUSTOM_IDENTIFIER KEPT_VERSION_NUM REPO_CATALOG AUTH_REQUEST_HEADER KEPT_VERSIONS
  REPO_URL="${1}"
  REPO_RELEASE_STORAGE="${2}"
  CUSTOM_IDENTIFIER="${3}"
  KEPT_VERSION_NUM="${4}"
  REPO_CATALOG="${5}"
  KEPT_VERSIONS="${6}"
  
  # use custom identifier if provided, otherwise extract from URL
  if [[ -n "$CUSTOM_IDENTIFIER" ]] && [[ "$CUSTOM_IDENTIFIER" != "null" ]]; then
    REPO_IDENTIFIER="$CUSTOM_IDENTIFIER"
  else
    REPO_IDENTIFIER=$(op_github_extract_repo_identifier "$REPO_URL")
  fi

  # configuration variables
  local REPO_TAGS_DATA_URL CMD_RETRIEVE_DATA REPO_TAGS_DATA TAG_STORAGE_PATH
  echo -e ""
  op_prompt_checkpoint "Downloading tags assets for ${BOLD}${GREEN}${REPO_IDENTIFIER}${NC}"

  # assemble release data url
  REPO_TAGS_DATA_URL="https://api.github.com/repos/${REPO_IDENTIFIER}/tags"

  # assemble auth header if access token is available
  if [[ -n "$GITHUB_ACCESS_TOKEN" ]];then
    AUTH_REQUEST_HEADER="-H 'Authorization: token $GITHUB_ACCESS_TOKEN'"
  fi

  # download release data
  CMD_RETRIEVE_DATA="curl -X GET --retry $DOWNLOAD_RETRY --retry-delay $DOWNLOAD_RETRY_DELAY $AUTH_REQUEST_HEADER -L -s '$REPO_TAGS_DATA_URL'"
  
  op_prompt_debug "${CMD_RETRIEVE_DATA}"
  
  op_run_cmd_with_result "$CMD_RETRIEVE_DATA"
  REPO_TAGS_DATA="$CMD_EXEC_STDOUT"

  # Check for error message in response (e.g., rate limit or not found)
  op_github_validate_response "$REPO_TAGS_DATA" "tags"
  local RET=$?
  if [[ $RET -eq 200 ]]; then return 0; elif [[ $RET -ne 0 ]]; then return $RET; fi

  # traverse release assets list
  local ASSET_LENGTH ASSET_DATA ASSET_NAME TAG_NAME CMD_DOWNLOAD_ASSET ASSET_DOWNLOAD_URL
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
  # include catalog in storage path
  if [[ -n "$REPO_CATALOG" ]] && [[ "$REPO_CATALOG" != "null" ]]; then
    TAG_STORAGE_PATH="${REPO_RELEASE_STORAGE}/${REPO_CATALOG}/${REPO_IDENTIFIER}/${TAG_NAME}"
  else
    TAG_STORAGE_PATH="${REPO_RELEASE_STORAGE}/${REPO_IDENTIFIER}/${TAG_NAME}"
  fi
  mkdir -p "$TAG_STORAGE_PATH"

  # skip already downloaded assets
  if [[ -f "${TAG_STORAGE_PATH}/${ASSET_NAME}" ]]; then
    op_prompt_info "Asset ${BOLD}${GREEN}${ASSET_NAME}${NC} >> Skipped: already downloaded"
    return 0
  fi

  CMD_DOWNLOAD_ASSET="curl -L --retry $DOWNLOAD_RETRY --retry-delay $DOWNLOAD_RETRY_DELAY --progress-bar -o '${TAG_STORAGE_PATH}/${ASSET_NAME}' '${ASSET_DOWNLOAD_URL}'"
  op_run_cmd "$CMD_DOWNLOAD_ASSET"

  # remove files if download operation didn't finish successfully
  if [[ "$?" -ne 0 ]]; then
    rm "${TAG_STORAGE_PATH}/${ASSET_NAME}"
  fi

  # cleanup old tags (include catalog in base path)
  if [[ -n "$REPO_CATALOG" ]] && [[ "$REPO_CATALOG" != "null" ]]; then
    op_cleanup_old_versions "${REPO_RELEASE_STORAGE}/${REPO_CATALOG}" "$REPO_IDENTIFIER" "$KEPT_VERSION_NUM" "tag" "$KEPT_VERSIONS"
  else
    op_cleanup_old_versions "$REPO_RELEASE_STORAGE" "$REPO_IDENTIFIER" "$KEPT_VERSION_NUM" "tag" "$KEPT_VERSIONS"
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
      if [[ "$ASSET_NAME" == *$KEYWORD* ]]; then
        op_prompt_info "Asset ${BOLD}${GREEN}${ASSET_NAME}${NC} >> Skipped: excluded by keyword ${YELLOW}${KEYWORD}${NC}"
        return 0
      fi
    done
  fi

  # skip already downloaded assets
  if [[ -f "${RELEASE_STORAGE_PATH}/${ASSET_NAME}" ]]; then
    op_prompt_info "Asset ${BOLD}${GREEN}${ASSET_NAME}${NC} >> Skipped: already ${YELLOW}downloaded${NC}"
    return 0
  fi

  CMD_DOWNLOAD_ASSET="curl -L --retry $DOWNLOAD_RETRY --retry-delay $DOWNLOAD_RETRY_DELAY --progress-bar -o '${RELEASE_STORAGE_PATH}/${ASSET_NAME}' '${ASSET_DOWNLOAD_URL}'"
  op_run_cmd "$CMD_DOWNLOAD_ASSET"

  # remove files if download operation didn't finish successfully
  if [[ "$?" -ne 0 ]]; then
    rm "${RELEASE_STORAGE_PATH}/${ASSET_NAME}"
  fi
}

# handle GitHub repository operations (sync, release, tag downloads)
op_handle_github_repo() {
  op_handle_repo "$@" op_github_download_release op_github_download_tag
}

op_load_github_access_token